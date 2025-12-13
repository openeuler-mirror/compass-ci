#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SuccessTaskValidator - 成功任务验证服务

这个模块实现了对已成功 bisect 任务的验证机制，通过边界验证确认
first_bad_commit 的准确性，并计算该 commit 引入的 errid 列表。

功能：
1. 扫描 bisect_status='success' 且未验证的任务
2. 进行边界验证（parent commit vs first_bad_commit）
3. 计算 errid diff（introduced_errids）
4. 保存验证结果到数据库
"""

import os
import sys
import time
import traceback
import threading
import subprocess
import json
from typing import Dict, Any, Optional, List
from collections import defaultdict

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger
from bisect_utils import write_regression_record

sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from manticore_simple import ManticoreClient
from py_bisect import GitBisect

# 导入父类 VerificationConsumer
from verification_consumer import VerificationConsumer
from bisect_utils import (
        mark_similar_wait_tasks_for_verification,
        mark_introduced_errid_tasks_for_verification
        )
from errid_intelligence import ErridIntelligence

class SuccessTaskValidator(VerificationConsumer):
    """
    成功任务验证服务

    继承 VerificationConsumer，复用边界验证逻辑，
    专门用于验证 bisect_status='success' 的历史任务
    """

    def __init__(self, client: ManticoreClient, config: Dict):
        """初始化验证服务"""
        super().__init__(client, config)

        # 验证配置参数（统一使用 verification_batch_size）
        self.validation_batch_size = config.get('verification_batch_size', 200)  # 修复：使用正确的键名和默认值
        self.validation_interval = config.get('validation_interval', 3600)  # 默认1小时

        # Initialize GitBisect instance for job submission
        self.bisect_instance = GitBisect(logger)

        logger.info(
            f"SuccessTaskValidator initialized | "
            f"batch_size: {self.validation_batch_size} | "
            f"interval: {self.validation_interval}s"
        )

    def scan_unverified_tasks(self, limit: int = None) -> List[Dict]:
        """
        扫描未验证的任务（只扫描 verifying 和 pending_verification 状态）

        代表任务（bisect_status='success' 且无 related_task_id）已经通过完整 bisect 验证，
        不需要额外验证。只有复用结果的相似任务需要验证边界条件。

        Args:
            limit: 返回的最大任务数，默认使用 validation_batch_size

        Returns:
            待验证的任务列表
        """
        try:
            batch_size = limit or self.validation_batch_size

            # 只查询两种状态的任务：
            # 1. verifying: 已提升，等待验证
            # 2. pending_verification: 等待代表任务完成
            sql_query = f"""
                SELECT id, bad_job_id, error_id, bisect_status, git_url,
                       updated_at, submit_time, j
                FROM bisect
                WHERE (
                     bisect_status = 'verifying'
                     AND j.related_task_id IS NOT NULL
                     AND (j.verification_status IS NULL OR j.verification_status != 'verified')
                     AND (j.verified_by_py_bisect IS NULL OR j.verified_by_py_bisect != true))
                ORDER BY
                    updated_at DESC
                LIMIT {batch_size}
            """

            logger.info(f"扫描未验证任务（verifying 和 pending_verification）| batch_size: {batch_size}")
            logger.debug(f"SQL查询: {sql_query[:200]}...")
            results = self.client.sql_select(sql_query)
            logger.info(f"SQL查询返回: {len(results) if results else 0} 条记录")

            if results:
                # 统计不同状态的任务数量
                verifying_count = sum(1 for t in results if t.get('bisect_status') == 'verifying')
                pending_count = sum(1 for t in results if t.get('bisect_status') == 'pending_verification')

                logger.info(
                    f"发现 {len(results)} 个待验证任务 | "
                    f"verifying: {verifying_count} | pending_verification: {pending_count}"
                )
            else:
                logger.info("未发现待验证任务")

            return results or []

        except Exception as e:
            logger.error(f"扫描未验证任务失败: {str(e)}")
            logger.error(traceback.format_exc())
            return []


    def group_tasks_by_repo(self, tasks: List[Dict]) -> Dict[str, List[Dict]]:
        """
        按仓库分组任务

        Args:
            tasks: 待验证任务列表

        Returns:
            按 git_url 分组的任务字典
        """
        tasks_by_repo = defaultdict(list)

        for task in tasks:
            task_id = task['id']
            bisect_status = task.get('bisect_status')
            git_url = task.get('git_url')

            # 如果任务没有 git_url，从关联任务获取
            if not git_url:
                try:
                    j_field = task.get('j', {})
                    if isinstance(j_field, str):
                        j_field = json.loads(j_field)

                    related_task_id = j_field.get('related_task_id')

                    if related_task_id:
                        # 查询关联任务的 git_url
                        related_task = self._get_related_task(str(related_task_id))
                        if related_task:
                            git_url = related_task.get('git_url')

                except Exception as e:
                    logger.warning(f"获取关联任务 git_url 失败 | task_id: {task_id} | error: {str(e)}")

            # 如果还是没有 git_url，跳过
            if not git_url:
                logger.warning(f"任务缺少 git_url，跳过 | task_id: {task_id} | status: {bisect_status}")
                continue

            tasks_by_repo[git_url].append(task)

        return tasks_by_repo

    def batch_submit_verification_jobs(
        self, repo_tasks: List[Dict], git_url: str, repo_manager
    ) -> Dict[str, int]:
        """
        批量提交验证作业（正确的批量流程）

        正确流程：
        1. 先获取一次共享仓库（只克隆一次）
        2. 循环所有任务，复用同一个仓库目录提交作业
        3. 避免每个任务重复调用 get_repo_dir

        Args:
            repo_tasks: 该仓库的任务列表（只包含 verifying 状态）
            git_url: 仓库 URL
            repo_manager: 仓库管理器实例

        Returns:
            {'submitted': 提交成功数, 'failed': 失败数}
        """
        submitted_count = 0
        failed_count = 0
        skipped_count = 0

        logger.info(f"开始批量提交验证作业 | repo: {git_url[:60]}... | tasks: {len(repo_tasks)}")

        # Step 1: 批量查询所有关联任务状态（避免 N+1 查询）
        related_task_ids = set()
        for task in repo_tasks:
            j_field = task.get('j', {})
            if isinstance(j_field, str):
                j_field = json.loads(j_field)

            related_task_id = j_field.get('related_task_id')
            if related_task_id:
                related_task_ids.add(str(related_task_id))

        # 批量查询
        related_tasks_map = {}
        if related_task_ids:
            try:
                ids_str = ','.join(related_task_ids)
                batch_query = f"""
                    SELECT id, bisect_status, first_bad_commit
                    FROM bisect
                    WHERE id IN ({ids_str})
                """
                batch_results = self.client.sql_select(batch_query)

                if batch_results:
                    for result in batch_results:
                        related_tasks_map[str(result['id'])] = result

                    logger.info(f"批量查询了 {len(related_task_ids)} 个关联任务 | 找到: {len(related_tasks_map)} 个")
            except Exception as e:
                logger.error(f"批量查询关联任务失败: {str(e)}")

        # Step 2: 筛选可提交的任务
        tasks_to_submit = []
        first_bad_job_id = None

        for task in repo_tasks:
            task_id = task['id']
            bad_job_id = task.get('bad_job_id')

            if not first_bad_job_id:
                first_bad_job_id = bad_job_id

            j_field = task.get('j', {})
            if isinstance(j_field, str):
                j_field = json.loads(j_field)

            # 检查是否已经提交过
            verification_jobs = j_field.get('verification_jobs', {})
            if verification_jobs and verification_jobs.get('status') in ['submitted', 'timeout']:
                skipped_count += 1
                logger.debug(f"验证作业已提交，跳过 | task_id: {task_id}")
                continue

            # 获取关联任务信息
            related_task_id = j_field.get('related_task_id')
            if not related_task_id:
                logger.warning(f"verifying 任务缺少 related_task_id | ID: {task_id}")
                failed_count += 1
                continue

            related_task = related_tasks_map.get(str(related_task_id))
            if not related_task:
                related_task = self._get_related_task(str(related_task_id))
                if not related_task:
                    logger.warning(f"关联任务不存在 | ID: {task_id} | related: {related_task_id}")
                    failed_count += 1
                    continue

            related_status = related_task.get('bisect_status')

            if related_status == 'failed':
                logger.warning(f"关联任务已失败，跳过 | ID: {task_id} | related: {related_task_id}")
                self._mark_task_failed(task_id, related_task_id, "related_task_failed")
                failed_count += 1
                continue

            if related_status != 'success':
                logger.debug(f"关联任务未成功，跳过 | ID: {task_id} | related: {related_task_id} | status: {related_status}")
                skipped_count += 1
                continue

            first_bad_commit = related_task.get('first_bad_commit')
            if not first_bad_commit:
                logger.warning(f"关联任务缺少 first_bad_commit | ID: {task_id} | related: {related_task_id}")
                failed_count += 1
                continue

            tasks_to_submit.append({
                'task_id': task_id,
                'bad_job_id': bad_job_id,
                'first_bad_commit': first_bad_commit,
                'error_id': task.get('error_id', ''),
                'related_task_id': related_task_id
            })

        logger.info(
            f"任务筛选完成 | 可提交: {len(tasks_to_submit)} | "
            f"跳过: {skipped_count} | 失败: {failed_count}"
        )

        if not tasks_to_submit:
            return {'submitted': 0, 'failed': failed_count}

        # Step 3: 获取共享仓库（只克隆一次）
        # 使用唯一的 batch_id 防止多个 validator 并行时互相冲突
        import uuid
        batch_id = f"batch_{int(time.time())}_{uuid.uuid4().hex[:8]}"
        try:
            logger.info(f"获取共享仓库 | batch_id: {batch_id} | git_url: {git_url[:60]}... | bad_job_id: {first_bad_job_id}")
            repo_dir, job_dir = repo_manager.get_repo_dir(
                batch_id,  # 使用唯一的 batch_id 防止并行冲突
                first_bad_job_id,
                git_url
            )
            logger.info(f"共享仓库获取成功 | repo_dir: {repo_dir}")
        except Exception as e:
            logger.error(f"获取共享仓库失败: {str(e)}")
            logger.error(traceback.format_exc())
            return {'submitted': 0, 'failed': len(tasks_to_submit)}

        # Step 4: 循环提交所有任务（复用同一个仓库目录）
        logger.info(f"开始循环提交 {len(tasks_to_submit)} 个任务（复用仓库 {repo_dir}）")

        for task_info in tasks_to_submit:
            task_id = task_info['task_id']
            first_bad_commit = task_info['first_bad_commit']
            error_id = task_info['error_id']
            bad_job_id = task_info['bad_job_id']

            # 在每次循环开始时检查仓库目录是否仍然存在
            if not os.path.exists(repo_dir):
                logger.error(f"共享仓库已被删除，终止批量提交 | repo_dir: {repo_dir}")
                failed_count += len(tasks_to_submit) - submitted_count - failed_count
                break

            try:
                # 使用共享仓库提交验证作业
                result = self._submit_verification_jobs_with_shared_repo(
                    task_id=task_id,
                    bad_job_id=bad_job_id,
                    first_bad_commit=first_bad_commit,
                    git_url=git_url,
                    error_id=error_id,
                    repo_dir=repo_dir
                )

                if result.get('status') == 'success':
                    submitted_count += 1
                    logger.info(
                        f"✓ 验证作业已提交 | task_id: {task_id} | "
                        f"parent_job: {result['parent_job_id']} | "
                        f"candidate_job: {result['candidate_job_id']}"
                    )
                else:
                    failed_count += 1
                    error = result.get('error', '')
                    logger.error(f"✗ 提交验证作业失败 | task_id: {task_id} | error: {error}")

                    # 如果是共享仓库不存在的错误，终止整个批次
                    if 'shared_repo_not_found' in error:
                        logger.error(f"共享仓库不存在，终止批量提交")
                        failed_count += len(tasks_to_submit) - submitted_count - failed_count
                        break

            except Exception as e:
                failed_count += 1
                logger.error(f"✗ 提交验证作业异常 | task_id: {task_id} | error: {str(e)}")
                logger.error(traceback.format_exc())

        logger.info(
            f"批量提交完成 | repo: {git_url[:60]}... | "
            f"submitted: {submitted_count} | failed: {failed_count} | skipped: {skipped_count}"
        )

        # 清理共享仓库
        try:
            repo_manager.release_repo_dir(repo_dir)
            logger.info(f"已清理批量验证仓库 | repo_dir: {repo_dir}")
        except Exception as e:
            logger.warning(f"清理批量验证仓库失败 | error: {str(e)}")

        return {'submitted': submitted_count, 'failed': failed_count}

    def _submit_verification_jobs_with_shared_repo(
        self, task_id: int, bad_job_id: str, first_bad_commit: str,
        git_url: str, error_id: str, repo_dir: str
    ) -> Dict:
        """
        使用共享仓库提交验证作业（不重复克隆）

        Args:
            task_id: 任务 ID
            bad_job_id: 坏作业 ID
            first_bad_commit: 候选 commit
            git_url: 仓库 URL
            error_id: 错误 ID
            repo_dir: 共享仓库目录

        Returns:
            {'status': 'success', 'parent_job_id': xxx, 'candidate_job_id': xxx}
        """
        # 检查共享仓库目录是否存在
        if not os.path.exists(repo_dir):
            error_msg = f"shared_repo_not_found: {repo_dir}"
            logger.error(f"共享仓库目录不存在 | task_id: {task_id} | repo_dir: {repo_dir}")
            return {
                'status': 'failed',
                'task_id': task_id,
                'error': error_msg
            }
        try:
            current_time = int(time.time())

            logger.info(
                f"提交验证作业（共享仓库）| task_id: {task_id} | "
                f"candidate: {first_bad_commit[:12]} | repo_dir: {repo_dir}"
            )

            # 获取父提交（支持自动 fetch 重试）
            parent_commit = None
            try:
                result = subprocess.run(
                    ['git', '-C', repo_dir, 'rev-parse', f'{first_bad_commit}^1'],
                    capture_output=True, text=True, check=True, timeout=60
                )
                parent_commit = result.stdout.strip()

                if not parent_commit:
                    return {'status': 'failed', 'error': 'failed_to_get_parent_commit'}

                logger.debug(f"父提交获取成功 | parent: {parent_commit[:12]}")

            except subprocess.CalledProcessError as e:
                logger.warning(f"首次获取父提交失败（可能是仓库落后）| error: {str(e)}")

                # 策略1: 尝试在 workspace 中 fetch 更新，然后重试
                try:
                    logger.info(f"尝试更新共享仓库 | repo_dir: {repo_dir}")
                    fetch_result = subprocess.run(
                        ['git', '-C', repo_dir, 'fetch', 'origin', '--tags'],
                        capture_output=True, text=True, timeout=120
                    )
                    if fetch_result.returncode == 0:
                        logger.info(f"仓库更新成功，重试获取父提交 | commit: {first_bad_commit[:12]}")

                        # 重试获取父提交
                        retry_result = subprocess.run(
                            ['git', '-C', repo_dir, 'rev-parse', f'{first_bad_commit}^1'],
                            capture_output=True, text=True, check=True, timeout=60
                        )
                        parent_commit = retry_result.stdout.strip()

                        if parent_commit:
                            logger.info(f"✓ fetch 后成功获取父提交 | parent: {parent_commit[:12]}")
                        else:
                            raise ValueError("Parent commit is empty after fetch")
                    else:
                        logger.error(f"Fetch 失败 | stderr: {fetch_result.stderr}")
                        raise subprocess.CalledProcessError(fetch_result.returncode, fetch_result.args)

                except Exception as fetch_err:
                    error_msg = f"get_parent_failed_after_fetch: {str(fetch_err)}"
                    logger.error(f"Fetch 重试后仍然失败 | error: {error_msg}")

                    # 注意：不要清理共享仓库目录，因为其他任务还在使用它
                    # 只返回当前任务失败，让外层循环继续处理其他任务

                    return {
                        'status': 'failed',
                        'task_id': task_id,
                        'error': error_msg
                    }

            # 使用 GitBisect 实例提交验证作业
            # 1. 提交父提交验证作业
            try:
                job_config_parent = self.bisect_instance.init_job_content(bad_job_id)

                # 替换commit为父提交
                if 'ss' in job_config_parent and 'linux' in job_config_parent['ss']:
                    job_config_parent['ss']['linux']['commit'] = parent_commit
                elif 'program' in job_config_parent and 'makepkg' in job_config_parent['program']:
                    job_config_parent['program']['makepkg']['commit'] = parent_commit
                else:
                    return {'status': 'failed', 'error': 'unrecognized_job_structure'}

                parent_job_id, parent_result_root, *_ = self.bisect_instance.submit_job(job_config_parent)
                logger.debug(f"父提交作业已提交 | job_id: {parent_job_id} | commit: {parent_commit[:12]}")

            except Exception as e:
                logger.error(f"提交父提交作业失败 | error: {str(e)}")
                return {'status': 'failed', 'error': f'submit_parent_failed: {str(e)}'}

            # 2. 提交候选提交验证作业
            try:
                job_config_candidate = self.bisect_instance.init_job_content(bad_job_id)

                # 替换commit为候选提交
                if 'ss' in job_config_candidate and 'linux' in job_config_candidate['ss']:
                    job_config_candidate['ss']['linux']['commit'] = first_bad_commit
                elif 'program' in job_config_candidate and 'makepkg' in job_config_candidate['program']:
                    job_config_candidate['program']['makepkg']['commit'] = first_bad_commit
                else:
                    return {'status': 'failed', 'error': 'unrecognized_job_structure'}

                candidate_job_id, candidate_result_root, *_ = self.bisect_instance.submit_job(job_config_candidate)
                logger.debug(f"候选提交作业已提交 | job_id: {candidate_job_id} | commit: {first_bad_commit[:12]}")

            except Exception as e:
                logger.error(f"提交候选提交作业失败 | error: {str(e)}")
                return {'status': 'failed', 'error': f'submit_candidate_failed: {str(e)}'}

            # 3. 保存作业信息到数据库
            update_doc = {
                "updated_at": current_time,
                "j": {
                    "verification_jobs": {
                        "status": "submitted",
                        "parent_job_id": parent_job_id,
                        "parent_result_root": parent_result_root,
                        "parent_commit": parent_commit,
                        "candidate_job_id": candidate_job_id,
                        "candidate_result_root": candidate_result_root,
                        "candidate_commit": first_bad_commit,
                        "git_url": git_url,
                        "error_id": error_id,
                        "submit_time": current_time,
                        "check_count": 0,
                        "last_check_time": current_time
                    }
                }
            }

            self.client.update("bisect", task_id, update_doc)

            return {
                'status': 'success',
                'parent_job_id': parent_job_id,
                'candidate_job_id': candidate_job_id
            }

        except Exception as e:
            logger.error(f"提交验证作业异常 | task_id: {task_id} | error: {str(e)}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': str(e)}

    def _mark_task_failed(self, task_id: int, related_task_id: str, reason: str):
        """标记任务失败（辅助方法）"""
        try:
            current_time = int(time.time())
            fail_doc = {
                "bisect_status": "failed",
                "updated_at": current_time,
                "j": {
                    "verification_status": "failed",
                    "verification_failure_reason": reason,
                    "related_task_id": str(related_task_id),
                    "failed_at": current_time
                }
            }
            self.client.update("bisect", task_id, fail_doc)
        except Exception as e:
            logger.error(f"标记任务失败异常 | task_id: {task_id} | error: {str(e)}")

    def check_verification_results_once(self, repo_manager=None, limit: int = 500, timeout_hours: int = 24):
        """
        单次检查验证作业结果（无循环，适合在外部循环中调用）

        Args:
            repo_manager: SharedRepoManager 实例，用于文件路径关联性检查
            limit: 每次检查的最大任务数
            timeout_hours: 验证作业超时时间（小时），默认 24 小时

        Returns:
            dict: 处理统计 {'checked': N, 'completed': N, 'failed': N, 'timeout': N, 'waiting': N, 'skipped': N}
        """
        errid_intelligence = ErridIntelligence()
        try:
            # 查询所有待检查的验证作业（排除已完成和已失败的）
            query = f"""
                SELECT id, j, bisect_status, updated_at
                FROM bisect
                WHERE bisect_status = 'verifying'
                AND j.verification_jobs IS NOT NULL
                AND (j.verification_jobs.status IS NULL
                     OR (j.verification_jobs.status != 'completed'
                         AND j.verification_jobs.status != 'failed'
                         AND j.verification_jobs.status != 'timeout'))
                LIMIT {limit}
            """

            pending_jobs = self.client.sql_select(query)

            if not pending_jobs:
                logger.debug("无待检查的验证作业")
                return {'checked': 0, 'completed': 0, 'failed': 0, 'timeout': 0, 'waiting': 0, 'skipped': 0}

            logger.info(f"检查 {len(pending_jobs)} 个验证作业")

            current_time = int(time.time())
            timeout_seconds = timeout_hours * 3600

            completed_count = 0
            failed_count = 0
            timeout_count = 0
            waiting_count = 0
            skipped_count = 0

            for job in pending_jobs:
                task_id = job['id']

                try:
                    j_field = job.get('j', {})
                    if isinstance(j_field, str):
                        j_field = json.loads(j_field)

                    verification_jobs = j_field.get('verification_jobs', {})

                    if not verification_jobs:
                        skipped_count += 1
                        continue

                    # 检查是否超时（使用 submit_time，如果不存在则使用 updated_at 作为兜底）
                    submitted_time = verification_jobs.get('submit_time')
                    if not submitted_time:
                        submitted_time = job.get('updated_at', 0)

                    if submitted_time and (current_time - submitted_time) > timeout_seconds:
                        logger.warning(f"验证作业超时 | task_id: {task_id} | 已等待: {(current_time - submitted_time)/3600:.1f} 小时")
                        self.mark_verification_timeout(task_id, reason="timeout_exceeded")
                        timeout_count += 1
                        continue

                    # 检查作业状态
                    parent_job_id = verification_jobs.get('parent_job_id')
                    candidate_job_id = verification_jobs.get('candidate_job_id')
                    parent_result_root = verification_jobs.get('parent_result_root')
                    candidate_result_root = verification_jobs.get('candidate_result_root')
                    error_id = verification_jobs.get('error_id', '')

                    if not parent_job_id or not candidate_job_id:
                        logger.warning(f"验证作业缺少 job_id | task_id: {task_id} | 标记为 wait")

                        # 标记为 wait，让任务回到自然队列重新处理
                        reset_doc = {
                            "bisect_status": "wait",
                            "updated_at": current_time,
                            "j": {}  # 清除验证相关字段
                        }

                        self.client.update("bisect", task_id, reset_doc)
                        failed_count += 1
                        continue

                    # 使用 GitBisect 实例检查作业状态
                    parent_stats, parent_health = self.bisect_instance._poll_job_stats(
                        parent_job_id, parent_result_root
                    )
                    candidate_stats, candidate_health = self.bisect_instance._poll_job_stats(
                        candidate_job_id, candidate_result_root
                    )

                    parent_completed = isinstance(parent_stats, dict) and parent_stats
                    candidate_completed = isinstance(candidate_stats, dict) and candidate_stats
                    verification_passed = None
                    parent_status = None
                    candidate_status = None

                    # 两个作业都已完成，分析结果
                    if (parent_completed and candidate_completed):
                        logger.info(f"验证作业已完成 | task_id: {task_id} | 开始分析结果")

                        # 检查父提交和候选提交的错误状态
                        parent_bad_job = self.bisect_instance.init_job_content(parent_job_id)
                        self.bisect_instance.is_build_task = self.bisect_instance._detect_build_task(parent_bad_job)
                        # _check_error_id 返回 (status, certainty, reason) 元组
                        parent_status, _, _ = self.bisect_instance._check_error_id(parent_stats, error_id, parent_health, parent_result_root)
                        candidate_status, _, _ = self.bisect_instance._check_error_id(candidate_stats, error_id, candidate_health, candidate_result_root)

                        verification_passed = (parent_status == 'good' and candidate_status == 'bad')
                        logger.info(
                            f"验证结果 | task_id: {task_id} | "
                            f"parent: {parent_status} | candidate: {candidate_status} | "
                            f"passed: {verification_passed}"
                        )
                    elif not parent_completed or not candidate_completed:
                        # 作业未完成，检查是否作业丢失（health 为 'job_not_found' 或 None 超过一定时间）
                        # 如果已经超过 6 小时且作业仍未找到，认为作业丢失
                        job_lost = False
                        lost_reason = ""

                        if parent_health == 'job_not_found' or candidate_health == 'job_not_found':
                            # 检查提交时间，如果超过 6 小时还是 job_not_found，认为丢失
                            submit_time = verification_jobs.get('submit_time', 0)
                            if submit_time and (current_time - submit_time) > 6 * 3600:
                                job_lost = True
                                lost_reason = f"job_not_found_after_6h (parent: {parent_health}, candidate: {candidate_health})"

                        if job_lost:
                            logger.warning(f"验证作业丢失 | task_id: {task_id} | reason: {lost_reason}")
                            self.mark_verification_timeout(task_id, reason=lost_reason)
                            timeout_count += 1
                            continue

                        # 正常等待
                        waiting_count += 1
                        logger.debug(
                            f"验证作业未完成 | task_id: {task_id} | "
                            f"parent_completed: {parent_completed} | candidate_completed: {candidate_completed}"
                        )
                        continue

                    if verification_passed:
                        # 验证成功：计算 errid diff 并标记为已验证
                        introduced_errids = self.calculate_errid_diff(
                            parent_job_id, candidate_job_id
                        )

                        logger.info(
                            f"errid diff 计算完成 | task_id: {task_id} | "
                            f"introduced_errids: {len(introduced_errids)}"
                        )

                        # 获取 first_bad_commit
                        first_bad_commit = verification_jobs.get('candidate_commit', '')
                        parent_commit = verification_jobs.get('parent_commit', '')

                        # 添加 git 验证检查（增强置信度）
                        git_verification = None
                        if repo_manager and error_id and self.bisect_instance.is_build_task and introduced_errids:
                            repo_dir = None  # 用于 finally 清理
                            try:
                                # 获取仓库目录（复用提交作业时的仓库）
                                git_url = verification_jobs.get('git_url', '')

                                if git_url and parent_commit and first_bad_commit:
                                    # 获取共享仓库
                                    repo_dir, _ = repo_manager.get_repo_dir(
                                        f"verify_{task_id}",
                                        parent_job_id,
                                        git_url
                                    )

                                    # 临时设置 work_dir 和 error_id 以使用 _verify_errids_with_git
                                    old_work_dir = self.bisect_instance.work_dir
                                    old_error_id = self.bisect_instance.error_id
                                    self.bisect_instance.work_dir = repo_dir
                                    self.bisect_instance.error_id = error_id

                                    try:
                                        # 使用 git 验证错误 ID
                                        git_verification = self.bisect_instance._verify_errids_with_git(
                                            parent_commit, first_bad_commit, introduced_errids
                                        )

                                        logger.info(
                                            f"git 验证完成 | task_id: {task_id} | "
                                            f"verified: {git_verification['verified']} | "
                                            f"confidence: {git_verification['confidence']} | "
                                            f"need_human_judgment: {git_verification['need_human_judgment']} | "
                                            f"reason: {git_verification['reason']}"
                                        )
                                    finally:
                                        # 恢复 work_dir 和 error_id
                                        self.bisect_instance.work_dir = old_work_dir
                                        self.bisect_instance.error_id = old_error_id
                            except Exception as e:
                                logger.warning(f"git 验证异常 | task_id: {task_id} | error: {str(e)}")
                            finally:
                                # 清理仓库目录
                                if repo_dir and repo_manager:
                                    try:
                                        repo_manager.release_repo_dir(repo_dir)
                                        logger.debug(f"已清理 git 验证仓库 | task_id: {task_id}")
                                    except Exception as e:
                                        logger.warning(f"清理 git 验证仓库失败 | task_id: {task_id} | error: {str(e)}")

                        # 标记为已验证
                        update_doc = {
                            "updated_at": current_time,
                            "bisect_status": "success",
                            "first_bad_commit": first_bad_commit,
                            "first_bad_id": candidate_job_id,
                            "first_result_root": candidate_result_root,
                            "last_error": "",  # 清空之前的错误信息
                            "j": {
                                "verification_status": "verified",
                                "verified_at": current_time,
                                "introduced_errids": introduced_errids,
                                "parent_job_id": parent_job_id,
                                "candidate_job_id": candidate_job_id,
                                "verification_method": "batch_async_validation",
                                "job_request_count": 2,  # 验证只用了2个job
                                "is_result_reused": True, # 明确标记这是结果复用
                                "job_reused_rate": 1.0,   # 标记为完全复用
                                "verification_jobs": {
                                    "status": "completed",
                                    "completed_at": current_time
                                }
                            }
                        }

                        # 添加 git 验证结果（如果有）
                        if git_verification:
                            update_doc["j"]["git_verification"] = {
                                "verified": git_verification.get("verified"),
                                "confidence": git_verification.get("confidence"),
                                "reason": git_verification.get("reason"),
                                "need_human_judgment": git_verification.get("need_human_judgment"),
                                "file_analysis": git_verification.get("file_analysis"),
                                "stats": git_verification.get("stats")
                            }

                        self.client.update("bisect", task_id, update_doc)
                        logger.info(f"任务已标记为已验证 | task_id: {task_id}")

                        # 写入 regression 表
                        try:
                            task_query = f"SELECT * FROM bisect WHERE id = {task_id} LIMIT 1"
                            task_results = self.client.sql_select(task_query)

                            if task_results:
                                full_task = task_results[0]
                                if not full_task.get('first_bad_commit'):
                                    full_task['first_bad_commit'] = first_bad_commit

                                write_regression_record(self.client, full_task, first_bad_commit)
                                logger.info(f"Regression 记录已写入 | task_id: {task_id}")

                                # 标记相似任务
                                mark_similar_wait_tasks_for_verification(
                                    self.client,
                                    errid_intelligence,
                                    full_task
                                )
                                mark_introduced_errid_tasks_for_verification(
                                    self.client,
                                    full_task
                                )
                        except Exception as e:
                            logger.error(f"Regression 写入异常 | task_id: {task_id} | error: {str(e)}")

                        completed_count += 1

                    else:
                        # 验证失败
                        reason = f"boundary_check_failed_parent_{parent_status}_candidate_{candidate_status}"

                        update_doc = {
                            "bisect_status": "wait",
                            "updated_at": current_time,
                            "j": {
                                "verification_status": "verification_failed",
                                "parent_job_id": parent_job_id,
                                "candidate_job_id": candidate_job_id,
                                "verification_failed_at": current_time,
                                "verification_failure_reason": reason,
                                "bisect_invalidated": True,
                                "bisect_invalidation_reason": "boundary_verification_failed",
                                "verification_jobs": {
                                    "status": "failed",
                                    "failed_at": current_time,
                                    "failure_reason": reason
                                }
                            }
                        }

                        self.client.update("bisect", task_id, update_doc)
                        logger.info(f"任务已标记为验证失败 | task_id: {task_id} | reason: {reason}")
                        failed_count += 1

                except Exception as e:
                    logger.error(f"检查验证作业失败 | task_id: {task_id} | error: {str(e)}")
                    logger.error(traceback.format_exc())
                    skipped_count += 1

            logger.info(
                f"验证作业检查完成 | total: {len(pending_jobs)} | "
                f"completed: {completed_count} | failed: {failed_count} | "
                f"timeout: {timeout_count} | waiting: {waiting_count} | skipped: {skipped_count}"
            )

            return {
                'checked': len(pending_jobs),
                'completed': completed_count,
                'failed': failed_count,
                'timeout': timeout_count,
                'waiting': waiting_count,
                'skipped': skipped_count
            }

        except Exception as e:
            logger.error(f"检查验证结果失败: {str(e)}")
            logger.error(traceback.format_exc())
            return {'checked': 0, 'completed': 0, 'failed': 0, 'timeout': 0, 'waiting': 0, 'skipped': 0}

    def mark_verification_timeout(self, task_id: int, reason: str = "timeout"):
        """标记验证作业超时，重置为 wait 状态重新走 bisect 流程

        Args:
            task_id: 任务 ID
            reason: 超时原因（默认 'timeout'，也可能是 'job_not_found_after_6h' 等）
        """
        try:
            current_time = int(time.time())

            # 先查询当前的超时次数
            current_timeout_count = 0
            try:
                query = f"SELECT j FROM bisect WHERE id = {task_id} LIMIT 1"
                results = self.client.sql_select(query)
                if results:
                    j_field = results[0].get('j', {})
                    if isinstance(j_field, str):
                        j_field = json.loads(j_field)
                    current_timeout_count = j_field.get('verification_timeout_count', 0)
            except Exception as e:
                logger.warning(f"查询超时次数失败 | task_id: {task_id} | error: {str(e)}")

            new_timeout_count = current_timeout_count + 1

            update_doc = {
                "bisect_status": "wait",  # 重置为 wait，让任务重新进入 bisect 流程
                "updated_at": current_time,
                "j": {
                    "verification_jobs": {
                        "status": "timeout",
                        "timeout_time": current_time,
                        "timeout_reason": reason
                    },
                    "verification_status": "timeout",
                    "verification_timeout_count": new_timeout_count,  # 累加超时次数
                    "last_timeout_reason": reason
                }
            }

            self.client.update("bisect", task_id, update_doc)
            logger.info(f"验证作业超时，已重置为 wait | task_id: {task_id} | reason: {reason} | timeout_count: {new_timeout_count}")

        except Exception as e:
            logger.error(f"标记验证超时失败 | task_id: {task_id} | error: {str(e)}")
 
def create_success_task_validator(config: Dict) -> SuccessTaskValidator:
    """创建成功任务验证服务实例"""
    client = ManticoreClient(
        host=config.get('manticore_host', 'localhost'),
        port=int(config.get('manticore_http_port', '9308'))
    )
    return SuccessTaskValidator(client, config)


if __name__ == '__main__':
    """测试验证服务"""
    # 配置
    config = {
        'manticore_host': os.environ.get('MANTICORE_HOST', 'localhost'),
        'manticore_http_port': os.environ.get('MANTICORE_HTTP_PORT', '9308'),
        'validation_batch_size': 5,
        'validation_interval': 3600,
        'verification_timeout': 3600,
        'parallel_verification_jobs': 2
    }

    # 创建验证服务
    validator = create_success_task_validator(config)

    # 运行一次验证周期
    stats = validator.run_validation_cycle()

    logger.info(f"验证完成 | 统计: {stats}")


