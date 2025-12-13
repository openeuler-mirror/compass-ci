#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
HeadValidator - HEAD 回归检测服务

这个模块实现了对已验证任务的 HEAD 回归检测，在最新 HEAD 上
检查已知问题是否仍然存在，及时发现回归情况。

功能：
1. 扫描已验证任务（verification_status='verified'）
2. 在最新 HEAD commit 提交测试
3. 检查 introduced_errids 是否仍存在
4. 更新 head_check_status 状态
5. 触发回归通知
"""

import os
import sys
import time
import subprocess
import traceback
from typing import Dict, Any, Optional, List, Tuple

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger

sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from manticore_simple import ManticoreClient
from py_bisect import GitBisect

# 导入共享工具
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/core')
from verification_consumer import VerificationConsumer
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from repo_manager import SharedRepoManager
from bisect_utils import extract_repo_name_from_url


class HeadValidator(VerificationConsumer):
    """
    HEAD 回归检测服务

    继承 VerificationConsumer，复用仓库管理和作业提交逻辑，
    定期检查已验证任务在最新 HEAD 的状态，
    发现问题回归或修复情况
    """

    def __init__(self, client: ManticoreClient, config: Dict):
        """初始化 HEAD 验证服务"""
        super().__init__(client, config)

        # 配置参数
        self.check_batch_size = config.get('head_check_batch_size', 10)
        self.check_interval = config.get('head_check_interval', 86400)  # 默认每天
        self.notification_webhook = config.get('notification_webhook_url', '')
        self.notification_email = config.get('notification_email', '')

        # 初始化 GitBisect 实例
        self.bisect_instance = GitBisect(logger)

        logger.info(
            f"HeadValidator initialized | "
            f"batch_size: {self.check_batch_size} | "
            f"interval: {self.check_interval}s"
        )

    def scan_verified_tasks(self, limit: int = None) -> List[Dict]:
        """
        扫描已验证任务

        Args:
            limit: 返回的最大任务数

        Returns:
            已验证的任务列表
        """
        try:
            batch_size = limit or self.check_batch_size

            # 查询条件：
            # 1. j.verification_status = 'verified'
            # 2. j.introduced_errids 非空
            # 3. head_check_completed 为空或 false（py_bisect 未完成 HEAD 检测）
            # 4. (head_check_status 为空 OR head_check_at < 24小时前)
            # 5. 未正在检查：head_check_status != 'checking'（避免重复提交）
            # 6. 非失败状态：head_check_status != 'failed'（失败不自动重试）
            # 7. 没有regressed_errids（避免重复检查已完成的任务）
            current_time = int(time.time())
            check_threshold = current_time - self.check_interval

            sql_query = f"""
                SELECT * FROM bisect
                WHERE j.verification_status = 'verified'
                AND j.introduced_errids IS NOT NULL
                AND (j.head_check_completed IS NULL OR j.head_check_completed = 0)
                AND (j.head_check_status IS NULL OR (
                    j.head_check_status != 'failed'
                    AND j.head_check_status != 'regressed'
                    AND j.head_check_status != 'fixed'
                ))
                AND (j.regressed_errids IS NULL OR j.regressed_errids = '')
                ORDER BY updated_at ASC
                LIMIT {batch_size}
            """

            logger.info(f"扫描已验证任务（跳过 py_bisect 已完成 HEAD 检测的任务） | batch_size: {batch_size}")
            results = self.client.sql_select(sql_query)

            if results:
                logger.info(f"发现 {len(results)} 个待检查任务")
            else:
                logger.info("未发现待检查任务")

            return results or []

        except Exception as e:
            logger.error(f"扫描已验证任务失败: {str(e)}")
            logger.error(traceback.format_exc())
            return []

    def get_head_commit(self, repo_dir: str) -> Optional[str]:
        """
        获取仓库的最新 HEAD commit

        Args:
            repo_dir: 仓库目录

        Returns:
            HEAD commit hash
        """
        try:
            result = subprocess.run(
                ['git', '-C', repo_dir, 'rev-parse', 'HEAD'],
                capture_output=True,
                text=True,
                check=True,
                timeout=60
            )

            head_commit = result.stdout.strip()
            logger.info(f"获取 HEAD commit 成功 | commit: {head_commit[:8]}")
            return head_commit

        except subprocess.CalledProcessError as e:
            logger.error(f"获取 HEAD commit 失败 | error: {e.stderr}")
            return None
        except subprocess.TimeoutExpired:
            logger.error("获取 HEAD commit 超时")
            return None
        except Exception as e:
            logger.error(f"获取 HEAD commit 异常: {str(e)}")
            return None

    def get_parent_commit(self, repo_dir: str, commit: str) -> Optional[str]:
        """
        获取指定 commit 的 parent commit (commit^)

        Args:
            repo_dir: 仓库目录
            commit: commit hash

        Returns:
            Parent commit hash
        """
        try:
            result = subprocess.run(
                ['git', '-C', repo_dir, 'rev-parse', f'{commit}^'],
                capture_output=True,
                text=True,
                check=True,
                timeout=60
            )

            parent_commit = result.stdout.strip()
            logger.info(f"获取 parent commit 成功 | commit: {commit[:8]} | parent: {parent_commit[:8]}")
            return parent_commit

        except subprocess.CalledProcessError as e:
            logger.error(f"获取 parent commit 失败 | commit: {commit[:8]} | error: {e.stderr}")
            return None
        except subprocess.TimeoutExpired:
            logger.error(f"获取 parent commit 超时 | commit: {commit[:8]}")
            return None
        except Exception as e:
            logger.error(f"获取 parent commit 异常 | commit: {commit[:8]} | error: {str(e)}")
            return None

    def submit_head_test(self, task: Dict, head_commit: str) -> Optional[Tuple[str, str]]:
        """
        在 HEAD commit 提交测试

        Args:
            task: bisect 任务记录
            head_commit: HEAD commit hash

        Returns:
            (job_id, result_root) 或 None
        """
        try:
            logger.info(f"提交 HEAD 测试 | task_id: {task['id']} | head: {head_commit[:8]}")

            # 使用 GitBisect 提交作业
            # 初始化作业配置
            bad_job_id = task.get('bad_job_id')
            if not bad_job_id:
                logger.error(f"缺少 bad_job_id | task_id: {task['id']}")
                return None

            job_config = self.bisect_instance.init_job_content(bad_job_id)

            # 替换 commit 为 HEAD
            if 'ss' in job_config and 'linux' in job_config['ss']:
                job_config['ss']['linux']['commit'] = head_commit
            elif 'program' in job_config and 'makepkg' in job_config['program']:
                job_config['program']['makepkg']['commit'] = head_commit
            else:
                logger.error(f"无法识别作业结构 | task_id: {task['id']}")
                return None

            # 提交作业
            job_id, result_root, *_ = self.bisect_instance.submit_job(job_config)
            logger.info(f"HEAD 测试提交成功 | job_id: {job_id} | task_id: {task['id']}")

            return (job_id, result_root)

        except Exception as e:
            logger.error(f"提交 HEAD 测试失败: {str(e)} | task_id: {task['id']}")
            logger.error(traceback.format_exc())
            return None

    def check_head_regression(self, task: Dict) -> Dict:
        """
        检查 HEAD 回归状态（增量验证：只验证状态变化）

        Args:
            task: bisect 任务记录

        Returns:
            检查结果字典
        """
        try:
            task_id = task['id']
            git_url = task.get('git_url')

            logger.info(f"检查 HEAD 回归 | task_id: {task_id}")

            if not git_url:
                error_msg = "missing_git_url"
                logger.error(f"{error_msg} | task_id: {task_id}")
                return {'status': 'failed', 'error': error_msg}

            # 获取原始 error_id（数据库中的 errid 字段）
            original_error_id = task.get('error_id')
            if not original_error_id:
                error_msg = "missing_original_error_id"
                logger.error(f"{error_msg} | task_id: {task_id}")
                return {'status': 'failed', 'error': error_msg}

            # 获取上一次的 HEAD check 状态（用于检测状态变化）
            previous_head_status = None
            j_field = task.get('j', {})
            if isinstance(j_field, str):
                import json
                try:
                    j_field = json.loads(j_field) if j_field else {}
                except:
                    j_field = {}
            previous_head_status = j_field.get('head_check_status')

            if previous_head_status:
                logger.info(f"上次 HEAD 状态: {previous_head_status} | task_id: {task_id}")
            else:
                logger.info(f"首次 HEAD 检查 | task_id: {task_id}")

            logger.info(f"检查原始 errid: {original_error_id} | task_id: {task_id}")

            # 获取仓库目录（使用基类方法）
            repo_dir, job_dir = self._get_repo_dir(task_id, task['bad_job_id'], git_url)

            try:
                # 获取 HEAD commit
                head_commit = self.get_head_commit(repo_dir)
                if not head_commit:
                    error_msg = "failed_to_get_head_commit"
                    logger.error(f"{error_msg} | task_id: {task_id}")
                    return {'status': 'failed', 'error': error_msg}

                # 提交 HEAD 测试
                head_result = self.submit_head_test(task, head_commit)
                if not head_result:
                    error_msg = "failed_to_submit_head_test"
                    logger.error(f"{error_msg} | task_id: {task_id}")
                    return {'status': 'failed', 'error': error_msg}

                head_job_id, head_result_root = head_result

                # 等待作业完成并使用综合构建日志分析检查原始 errid
                job_stats, job_health = self.bisect_instance._poll_job_stats(head_job_id, head_result_root)

                # 使用 py_bisect 的综合构建日志分析方法检查原始 errid
                # _check_error_id 返回 (status, certainty, reason) 元组
                error_status, _, _ = self.bisect_instance._check_error_id(job_stats, original_error_id, job_health, head_result_root)

                # 检查回归：原始 errid 是否仍然存在
                regressed = (error_status == 'bad')
                new_status = 'regressed' if regressed else 'fixed'
                regressed_errids = [original_error_id] if regressed else []

                logger.info(f"HEAD 作业完成 | 使用构建日志分析 | 原始 errid 状态: {new_status} | job_id: {head_job_id}")

                # 检测状态变化
                status_changed = (previous_head_status is not None and previous_head_status != new_status)

                if status_changed:
                    logger.warning(
                        f"HEAD 状态变化 | task_id: {task_id} | "
                        f"{previous_head_status} → {new_status} | 需要验证"
                    )

                    # 状态变化需要验证：提交 HEAD^ (parent) 的测试进行边界验证
                    verification_needed = True
                else:
                    logger.info(
                        f"HEAD 状态未变或首次检查 | task_id: {task_id} | "
                        f"status: {new_status} | 无需验证"
                    )
                    verification_needed = False

                # 如果需要验证（状态变化），进行边界验证
                verified = False
                final_status = new_status  # 默认使用新检测到的状态

                if verification_needed:
                    # 进行边界验证：测试 HEAD^ (parent commit)
                    parent_commit = self.get_parent_commit(repo_dir, head_commit)
                    if parent_commit:
                        logger.info(f"开始边界验证 | HEAD: {head_commit[:8]} | parent: {parent_commit[:8]} | task_id: {task_id}")

                        # 提交 parent commit 测试
                        parent_result = self.submit_head_test(task, parent_commit)
                        if parent_result:
                            parent_job_id, parent_result_root = parent_result

                            # 等待 parent 测试完成
                            parent_job_stats, parent_job_health = self.bisect_instance._poll_job_stats(parent_job_id, parent_result_root)
                            # _check_error_id 返回 (status, certainty, reason) 元组
                            parent_error_status, _, _ = self.bisect_instance._check_error_id(parent_job_stats, original_error_id, parent_job_health, parent_result_root)

                            parent_status = 'bad' if parent_error_status == 'bad' else 'good'

                            logger.info(
                                f"边界验证完成 | HEAD: {new_status} | parent: {parent_status} | "
                                f"task_id: {task_id} | parent_job: {parent_job_id}"
                            )

                            # 验证边界条件
                            if new_status == 'regressed' and parent_status == 'good':
                                # regressed + parent good = 确认新回归
                                verified = True
                                final_status = 'regressed'
                                logger.warning(f"验证通过：确认新回归 | task_id: {task_id}")
                                # 触发通知
                                self.trigger_notification(task, 'regressed', regressed_errids)

                            elif new_status == 'fixed' and parent_status == 'bad':
                                # fixed + parent bad = 确认已修复（但parent有问题，可能不稳定）
                                verified = True
                                final_status = 'fixed'
                                logger.info(f"验证通过：确认已修复 | task_id: {task_id}")

                            elif new_status == 'fixed' and parent_status == 'good':
                                # fixed + parent good = 确认已修复（稳定）
                                verified = True
                                final_status = 'fixed'
                                logger.info(f"验证通过：确认已修复（稳定） | task_id: {task_id}")

                            elif new_status == 'regressed' and parent_status == 'bad':
                                # regressed + parent bad = 边界条件不满足，可能是 flaky test
                                verified = False
                                final_status = 'unverifiable'
                                logger.warning(
                                    f"边界验证失败：HEAD=bad, parent=bad | task_id: {task_id} | "
                                    f"可能是 flaky test，标记为 unverifiable"
                                )

                            else:
                                # 其他情况
                                verified = False
                                final_status = 'unverifiable'
                                logger.warning(f"边界验证结果异常 | task_id: {task_id}")

                        else:
                            logger.error(f"提交 parent commit 测试失败 | task_id: {task_id}")
                            verified = False
                            final_status = new_status  # 无法验证，使用原始状态
                    else:
                        logger.error(f"获取 parent commit 失败 | task_id: {task_id}")
                        verified = False
                        final_status = new_status  # 无法验证，使用原始状态
                else:
                    # 首次检查或状态未变，不需要验证
                    verified = True  # 认为是可信的
                    final_status = new_status

                # 更新数据库
                self.update_head_check_status(
                    task_id, final_status, head_commit, head_job_id, regressed_errids,
                    verified=verified, status_changed=status_changed
                )

                # 只在以下情况生成/更新报告：
                # 1. 首次检查 (previous_head_status is None)
                # 2. 状态变化且验证通过 (status_changed and verified)
                should_generate_report = (previous_head_status is None) or (status_changed and verified)

                if should_generate_report:
                    # 生成 bisect 成功报告（包含 HEAD check 结果）
                    try:
                        # 重新查询任务以获取更新后的完整信息
                        updated_tasks = self.client.sql_select(f"SELECT * FROM bisect WHERE id = {task_id}")
                        if updated_tasks:
                            updated_task = updated_tasks[0]

                            # 获取 job 信息用于报告
                            bad_job_id = task.get('bad_job_id')
                            job_info = None
                            if bad_job_id:
                                try:
                                    job_query = f"SELECT * FROM jobs WHERE id = {int(bad_job_id)} LIMIT 1"
                                    job_results = self.client.sql_select(job_query)
                                    if job_results and len(job_results) > 0:
                                        job_info = job_results[0]
                                except Exception as e:
                                    logger.warning(f"获取 job 信息失败 | job_id: {bad_job_id} | error: {str(e)}")

                            # 从 j 字段获取 introduced_errids
                            j_field = updated_task.get('j', {})
                            if isinstance(j_field, str):
                                import json
                                try:
                                    j_field = json.loads(j_field) if j_field else {}
                                except:
                                    j_field = {}
                            introduced_errids = j_field.get('introduced_errids', []) or []

                            # 写入通知报告（固定文件名，每次更新）
                            report_path = self.notification_writer.write_bisect_success_report(
                                updated_task,
                                job_info=job_info,
                                introduced_errids=introduced_errids
                            )
                            if report_path:
                                logger.info(f"Bisect 成功报告已生成/更新 | task_id: {task_id} | HEAD: {final_status} | verified: {verified} | path: {report_path}")
                            else:
                                logger.warning(f"Bisect 成功报告生成失败 | task_id: {task_id}")
                        else:
                            logger.warning(f"无法获取更新后的任务信息 | task_id: {task_id}")
                    except Exception as e:
                        logger.error(f"Bisect 成功报告生成异常 | task_id: {task_id} | error: {str(e)}")
                        import traceback
                        logger.error(traceback.format_exc())
                else:
                    logger.info(f"状态未变化，跳过报告生成 | task_id: {task_id} | status: {final_status}")

                return {
                    'status': 'success',
                    'task_id': task_id,
                    'head_check_status': final_status,
                    'head_commit': head_commit,
                    'head_job_id': head_job_id,
                    'regressed_errids': regressed_errids,
                    'verified': verified,
                    'status_changed': status_changed
                }

            finally:
                # 释放仓库回池（使用基类方法）
                self._release_repo_to_pool(repo_dir, job_dir)

        except Exception as e:
            error_msg = f"check_head_regression_exception: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task.get('id', 'unknown')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg}

    def update_head_check_status(self, task_id: int, status: str, head_commit: str,
                                 head_job_id: str, regressed_errids: List[str],
                                 verified: bool = True, status_changed: bool = False):
        """
        更新 HEAD 检查状态

        Args:
            task_id: 任务ID
            status: 状态（'regressed', 'fixed', 'unverifiable'）
            head_commit: HEAD commit hash
            head_job_id: HEAD 测试作业ID
            regressed_errids: 回归的 errid 列表
            verified: 是否经过验证
            status_changed: 状态是否发生变化
        """
        try:
            current_time = int(time.time())

            # 先获取现有的 j 字段，避免覆盖
            existing_j = {}
            try:
                task = self.client.sql_select_one(f"SELECT j FROM bisect WHERE id = {task_id}")
                if task and 'j' in task:
                    j_field = task['j']
                    if isinstance(j_field, dict):
                        existing_j = j_field
            except Exception as e:
                logger.warning(f"解析现有 J 字段失败 | task_id: {task_id} | error: {str(e)}")

            # 合并 HEAD 检查字段到现有 J 字段
            updated_j = {
                **existing_j,  # 保留现有字段（包括 verification_status, introduced_errids 等）
                "head_check_status": status,
                "head_check_at": current_time,
                "head_check_commit": head_commit,
                "head_check_job_id": head_job_id,
                "head_check_source": "head_validator",
                "head_check_verified": verified,
                "head_check_status_changed": status_changed,
                "regressed_errids": regressed_errids if status == 'regressed' else []
            }

            update_doc = {
                "updated_at": current_time,
                "j": updated_j
            }

            update_result = self.client.update("bisect", task_id, update_doc)

            if update_result:
                logger.info(f"HEAD 检查状态更新 | task_id: {task_id} | status: {status}")
            else:
                logger.error(f"更新数据库失败 | task_id: {task_id}")

        except Exception as e:
            logger.error(f"更新 HEAD 检查状态失败: {str(e)} | task_id: {task_id}")
            logger.error(traceback.format_exc())

    def trigger_notification(self, task: Dict, status: str, regressed_errids: List[str]):
        """
        触发 HEAD 检查通知

        Args:
            task: 任务记录
            status: 状态 ('regressed' 或 'fixed')
            regressed_errids: 回归的 errid 列表
        """
        try:
            task_id = task['id']
            first_bad_commit = task.get('first_bad_commit', 'N/A')
            git_url = task.get('git_url', 'N/A')

            if status == 'regressed':
                # 回归告警
                message = (
                    f"【HEAD 回归告警】\n"
                    f"任务ID: {task_id}\n"
                    f"First Bad Commit: {first_bad_commit}\n"
                    f"回归 Errids: {len(regressed_errids)}\n"
                    f"Sample: {regressed_errids[:3]}\n"
                    f"Git URL: {git_url}"
                )

                logger.warning("=" * 60)
                logger.warning(message)
                logger.warning("=" * 60)

                # 写入文件通知（修复参数错误）
                self.notification_writer.write_head_regression_alert(
                    task=task,  # ✅ 传完整 task 对象
                    regressed_errids=regressed_errids
                )
                logger.info(f"HEAD 回归通知已写入 | task_id: {task_id}")

            elif status == 'fixed':
                # 修复报告（好消息！）
                j_data = task.get('j', {})
                introduced_errids = j_data.get('introduced_errids', [])

                message = (
                    f"【HEAD 修复报告】✅\n"
                    f"任务ID: {task_id}\n"
                    f"First Bad Commit: {first_bad_commit}\n"
                    f"问题已在 HEAD 修复！\n"
                    f"原始 Errids: {len(introduced_errids)}\n"
                    f"Git URL: {git_url}"
                )

                logger.info("=" * 60)
                logger.info(message)
                logger.info("=" * 60)

                # 写入修复报告
                self.notification_writer.write_head_fixed_report(
                    task=task,
                    introduced_errids=introduced_errids
                )
                logger.info(f"HEAD 修复报告已写入 | task_id: {task_id}")

            # TODO: 实现 webhook/email 通知
            if self.notification_webhook:
                logger.info(f"TODO: 发送 webhook 通知到 {self.notification_webhook}")

            if self.notification_email:
                logger.info(f"TODO: 发送邮件通知到 {self.notification_email}")

        except Exception as e:
            logger.error(f"触发通知失败: {str(e)}")
            logger.error(traceback.format_exc())


    def run_head_check_cycle(self) -> Dict[str, int]:
        """
        运行一次 HEAD 检查周期

        Returns:
            统计信息字典
        """
        try:
            logger.info("=" * 60)
            logger.info("开始 HEAD 回归检测周期")
            logger.info("=" * 60)

            # 扫描已验证任务
            verified_tasks = self.scan_verified_tasks()

            if not verified_tasks:
                logger.info("本周期无待检查任务")
                return {
                    'scanned': 0,
                    'regressed': 0,
                    'fixed': 0,
                    'failed': 0
                }

            # 检查统计
            stats = {
                'scanned': len(verified_tasks),
                'regressed': 0,
                'fixed': 0,
                'failed': 0
            }

            # 逐个检查任务
            for task in verified_tasks:
                try:
                    result = self.check_head_regression(task)

                    if result.get('status') == 'success':
                        head_status = result.get('head_check_status')
                        if head_status == 'regressed':
                            stats['regressed'] += 1
                        elif head_status == 'fixed':
                            stats['fixed'] += 1
                    else:
                        stats['failed'] += 1

                except Exception as e:
                    logger.error(f"检查任务异常: {str(e)} | task_id: {task.get('id')}")
                    stats['failed'] += 1

            # 输出统计信息
            logger.info("=" * 60)
            logger.info(
                f"HEAD 检查周期完成 | "
                f"扫描: {stats['scanned']} | "
                f"回归: {stats['regressed']} | "
                f"修复: {stats['fixed']} | "
                f"失败: {stats['failed']}"
            )
            logger.info("=" * 60)

            return stats

        except Exception as e:
            logger.error(f"HEAD 检查周期异常: {str(e)}")
            logger.error(traceback.format_exc())
            return {
                'scanned': 0,
                'regressed': 0,
                'fixed': 0,
                'failed': 0,
                'error': str(e)
            }


    def _submit_head_test_async(self, task, head_commit):
        """异步提交 HEAD 测试（不等待作业完成）"""
        try:
            task_id = task['id']

            # 提交 HEAD 测试
            head_result = self.submit_head_test(task, head_commit)

            if head_result:
                head_job_id, head_result_root = head_result

                # 解析 j 字段获取 introduced_errids
                j_field = task.get('j', {})
                if isinstance(j_field, str):
                    import json
                    j_field = json.loads(j_field)

                introduced_errids = j_field.get('introduced_errids', [])

                # 保存作业ID到数据库（合并现有 J 字段，避免覆盖 verification 数据）
                current_time = int(time.time())

                # 读取现有的 J 字段
                existing_j = {}
                try:
                    j_field = task.get('j', {})
                    if isinstance(j_field, str):
                        import json
                        j_field = json.loads(j_field)
                    existing_j = j_field if isinstance(j_field, dict) else {}
                except Exception as e:
                    logger.warning(f"解析现有 J 字段失败 | task_id: {task_id} | error: {str(e)}")

                # 合并 HEAD 检查字段到现有 J 字段
                updated_j = {
                    **existing_j,  # 保留现有字段（包括 introduced_errids）
                    "head_check_status": "checking",
                    "head_check_job_id": head_job_id,
                    "head_check_result_root": head_result_root,
                    "head_check_commit": head_commit,
                    "head_check_source": "head_validator",
                    "head_check_submitted_at": current_time
                    # 注意：不再存储 head_check_target_errids，直接使用 introduced_errids
                }

                update_doc = {
                    "updated_at": current_time,
                    "j": updated_j
                }
                self.client.update("bisect", task_id, update_doc)

                return {
                    'submitted': True,
                    'head_job_id': head_job_id
                }
            else:
                return {'submitted': False, 'error': 'failed_to_submit_head_test'}

        except Exception as e:
            logger.error(f"异步提交 HEAD 测试异常 | task_id: {task.get('id')} | error: {str(e)}")
            logger.error(traceback.format_exc())
            return {'submitted': False, 'error': str(e)}

    def _poll_head_test_results(self):
        """轮询 HEAD 测试中的任务，检查作业是否完成"""
        try:
            # 查询 head_check_status = 'checking' 的任务
            # 优先处理提交时间早的任务，避免部分任务永远不被选中
            sql_query = """
                SELECT id, error_id, j
                FROM bisect
                WHERE j.head_check_status = 'checking'
                ORDER BY j.head_check_submitted_at ASC
                LIMIT 200
            """
            checking_tasks = self.client.sql_select(sql_query)

            if not checking_tasks:
                return

            logger.info(f"轮询 HEAD 测试中的任务: {len(checking_tasks)} 个")

            completed_count = 0
            regressed_count = 0
            fixed_count = 0

            for task in checking_tasks:
                try:
                    task_id = task['id']
                    j_field = task.get('j', {})
                    if isinstance(j_field, str):
                        import json
                        j_field = json.loads(j_field)

                    head_job_id = j_field.get('head_check_job_id')
                    head_result_root = j_field.get('head_check_result_root')
                    head_commit = j_field.get('head_check_commit')
                    target_errids = j_field.get('introduced_errids', [])  # 直接使用 introduced_errids
                    submitted_at = j_field.get('head_check_submitted_at', 0)

                    if not head_job_id or not target_errids:
                        logger.warning(
                            f"HEAD测试任务缺少必要信息 | task_id: {task_id} | "
                            f"head_job_id: {head_job_id} | introduced_errids: {len(target_errids) if target_errids else 0}"
                        )
                        continue

                    # 检查作业是否完成（按照原版 py_bisect 逻辑）
                    try:
                        head_stats, head_health = self.bisect_instance._poll_job_stats(head_job_id, head_result_root)

                        # 检查作业是否已完成
                        if not (isinstance(head_stats, dict) and head_stats):
                            logger.debug(f"HEAD 测试作业未完成 | task_id: {task_id} | job_id: {head_job_id}")
                            continue

                    except Exception as e:
                        logger.error(f"检查 HEAD 测试作业状态失败 | task_id: {task_id} | job_id: {head_job_id} | error: {str(e)}")
                        continue

                    # 作业已完成，开始分析回归状态
                    logger.info(f"HEAD测试已完成 | task_id: {task_id} | 开始分析回归状态")
                    # 分析回归状态并更新结果
                    status = self._finalize_head_check(task, head_job_id, head_commit, target_errids)

                    completed_count += 1
                    if status == 'regressed':
                        regressed_count += 1
                    elif status == 'fixed':
                        fixed_count += 1

                except Exception as e:
                    logger.error(f"轮询 HEAD 测试异常 | task_id: {task.get('id')} | error: {str(e)}")

            if completed_count > 0:
                logger.info(
                    f"本轮完成 HEAD 检查: {completed_count} 个任务 | "
                    f"回归: {regressed_count} | 修复: {fixed_count}"
                )

        except Exception as e:
            logger.error(f"轮询 HEAD 测试结果异常: {str(e)}")
            logger.error(traceback.format_exc())

    def _finalize_head_check(self, task, head_job_id, head_commit, target_errids):
        """完成 HEAD 检查：分析回归状态并更新数据库"""
        try:
            task_id = task['id']

            # 获取 HEAD 作业的 errids
            job_stats, job_health = self.bisect_instance._poll_job_stats(head_job_id)

            if not job_stats:
                logger.warning(f"HEAD 作业无 stats | job_id: {head_job_id}")
                head_errids = []
            else:
                head_errids = list(job_stats.keys())

            logger.info(f"HEAD 作业完成 | errids: {len(head_errids)} | job_id: {head_job_id}")

            # 检查回归：target_errids 中的任意一个存在于 head_errids 中
            regressed_errids = [e for e in target_errids if e in head_errids]

            if regressed_errids:
                # 问题回归
                status = 'regressed'
                logger.warning(
                    f"检测到回归 | task_id: {task_id} | "
                    f"regressed: {len(regressed_errids)}/{len(target_errids)}"
                )
                logger.warning(f"回归 errids: {regressed_errids[:3]}...")

                # 触发通知
                self.trigger_notification(task, 'regressed', regressed_errids)
            else:
                # 问题已修复
                status = 'fixed'
                logger.info(f"问题已修复 | task_id: {task_id} | HEAD 无已知 errids")

                # 触发修复通知（好消息！）
                self.trigger_notification(task, 'fixed', [])

            # 更新数据库（合并现有 J 字段）
            current_time = int(time.time())

            # 读取现有的 J 字段
            existing_j = {}
            try:
                j_field = task.get('j', {})
                if isinstance(j_field, str):
                    import json
                    j_field = json.loads(j_field)
                existing_j = j_field if isinstance(j_field, dict) else {}
            except Exception as e:
                logger.warning(f"解析现有 J 字段失败 | task_id: {task_id} | error: {str(e)}")

            # 合并 HEAD 检查完成字段到现有 J 字段
            updated_j = {
                **existing_j,  # 保留现有字段（包括 verification 数据）
                "head_check_status": status,
                "head_check_at": current_time,
                "head_check_commit": head_commit,
                "head_check_job_id": head_job_id,
                "head_check_source": "head_validator",
                "regressed_errids": regressed_errids if status == 'regressed' else [],
                "head_check_completed_at": current_time
            }

            update_doc = {
                "updated_at": current_time,
                "j": updated_j
            }

            # 执行数据库更新并检查结果
            update_result = self.client.update("bisect", task_id, update_doc)

            if not update_result:
                logger.error(
                    f"HEAD 检查数据库更新失败 | task_id: {task_id} | status: {status} | "
                    f"update_doc: {update_doc}"
                )
                return 'failed'

            logger.info(f"HEAD 检查完成 | task_id: {task_id} | status: {status}")
            return status

        except Exception as e:
            logger.error(f"完成 HEAD 检查异常 | task_id: {task.get('id')} | error: {str(e)}")
            logger.error(traceback.format_exc())
            self._mark_head_check_failed(task, f"HEAD 检查异常: {str(e)}")
            return 'failed'

    def _mark_head_check_failed(self, task: dict, reason: str):
        """标记 HEAD 检查失败

        Args:
            task: 完整的任务字典对象
            reason: 失败原因
        """
        try:
            task_id = task.get('id') if isinstance(task, dict) else task
            current_time = int(time.time())

            # 读取现有的 J 字段
            existing_j = {}
            try:
                j_field = task.get('j', {}) if isinstance(task, dict) else {}
                if isinstance(j_field, str):
                    import json
                    j_field = json.loads(j_field)
                existing_j = j_field if isinstance(j_field, dict) else {}
            except Exception as e:
                logger.warning(f"解析现有 J 字段失败 | task_id: {task_id} | error: {str(e)}")

            # 合并 HEAD 检查失败字段到现有 J 字段
            updated_j = {
                **existing_j,  # 保留现有字段
                "head_check_status": "failed",
                "head_check_source": "head_validator",
                "head_check_failure_reason": reason,
                "head_check_failed_at": current_time
            }

            update_doc = {
                "updated_at": current_time,
                "j": updated_j
            }
            self.client.update("bisect", task_id, update_doc)
            logger.info(f"HEAD 检查失败已记录 | task_id: {task_id} | reason: {reason}")

            # 写入通知文件（仅超时情况） - 直接使用传入的 task 对象
            if "超时" in reason:
                try:
                    self.notification_writer.write_timeout_alert(
                        task_id=task_id,
                        error_id=task.get('error_id', 'unknown'),
                        timeout_type='head_check',
                        reason=reason
                    )
                    logger.info(f"HEAD 检查超时通知已写入文件 | task_id: {task_id}")
                except Exception as e:
                    logger.error(f"写入 HEAD 检查超时通知异常 | task_id: {task_id} | error: {str(e)}")

        except Exception as e:
            task_id = task.get('id') if isinstance(task, dict) else task
            logger.error(f"标记 HEAD 检查失败异常 | task_id: {task_id} | error: {str(e)}")

def create_head_validator(config: Dict) -> HeadValidator:
    """创建 HEAD 验证服务实例"""
    client = ManticoreClient(
        host=config.get('manticore_host', 'localhost'),
        port=int(config.get('manticore_http_port', '9308'))
    )
    return HeadValidator(client, config)


if __name__ == '__main__':
    """测试 HEAD 验证服务"""
    # 配置
    config = {
        'manticore_host': os.environ.get('MANTICORE_HOST', 'localhost'),
        'manticore_http_port': os.environ.get('MANTICORE_HTTP_PORT', '9308'),
        'head_check_batch_size': 5,
        'head_check_interval': 86400,  # 每天
        'notification_webhook_url': '',
        'notification_email': ''
    }

    # 创建验证服务
    validator = create_head_validator(config)

    # 运行一次检查周期
    stats = validator.run_head_check_cycle()

    logger.info(f"HEAD 检查完成 | 统计: {stats}")
