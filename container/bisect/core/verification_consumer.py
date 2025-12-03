#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
VerificationConsumer - 边界验证消费者

这个模块实现了异步边界验证机制，用于验证相似任务的候选commit是否正确，
通过低成本的单点测试来复用已有bisect结果，避免重复的完整bisect操作。
"""

import os
import sys
import time
import subprocess
import traceback
import threading
import requests
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, Any, Optional, List, Tuple
from datetime import datetime

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger
from notification_writer import NotificationWriter
from repo_manager import SharedRepoManager
from bisect_utils import extract_git_url_from_full_text_kv, extract_repo_name_from_url, write_regression_record

sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from manticore_simple import ManticoreClient
from py_bisect import GitBisect


class VerificationConsumer:
    """边界验证消费者 - 处理pending_verification状态的任务"""

    def __init__(self, client: ManticoreClient, config: Dict):
        self.client = client
        self.config = config
        # 使用验证器专用信号量（2并发）
        self.repo_manager = SharedRepoManager()
        self.running = True

        # 验证配置参数
        self.verification_timeout = config.get('verification_timeout', 3600)  # 1小时
        self.parallel_jobs = config.get('parallel_verification_jobs', 2)  # 并行验证作业数
        self.max_retry_count = config.get('verification_max_retry', 3)  # 最大重试次数

        # 初始化通知服务
        notification_dir = config.get('notification_dir', '/result/bisect/notifications')
        self.notification_writer = NotificationWriter(notification_dir=notification_dir)

        logger.info(
            f"VerificationConsumer initialized | "
            f"timeout: {self.verification_timeout}s | "
            f"parallel_jobs: {self.parallel_jobs} | "
            f"notification_dir: {notification_dir}"
        )

    def process_success_verify(self, task: Dict) -> Dict:
        try:
            task_id = int(task['id'])
            logger.info(f"开始验证任务 | ID: {task_id}")

            # 获取任务元数据（包括 introduced_errids）
            task_metadata = self._get_task_metadata(task)
            if not task_metadata:
                error_msg = "无法获取任务元数据"
                logger.error(f"{error_msg} | ID: {task_id}")
                return {'status': 'failed', 'error': error_msg, 'id': task_id}

            candidate_commit = task_metadata.get('candidate_commit')
            related_task_id = task_metadata.get('related_task_id')
            introduced_errids = task_metadata.get('introduced_errids', [])
            parent_job_id = task_metadata.get('parent_job_id')
            parent_commit = task_metadata.get('parent_commit')

            if not candidate_commit or not related_task_id:
                error_msg = "缺少候选commit或关联任务ID"
                logger.error(f"{error_msg} | ID: {task_id} | metadata: {task_metadata}")
                return {'status': 'failed', 'error': error_msg, 'id': task_id}

            logger.info(f"验证参数 | 候选commit: {candidate_commit} | 关联任务: {related_task_id}")
            logger.info(f"关联任务的 introduced_errids: {len(introduced_errids)} 个")
            if introduced_errids and len(introduced_errids) <= 5:
                logger.info(f"  Sample: {introduced_errids[:5]}")

            # 获取Git仓库信息（优先级：task -> 关联任务元数据 -> 相关任务查询 -> jobs表）
            git_url = task.get('git_url')

            if not git_url:
                # 尝试从元数据中获取（新逻辑）
                git_url = task_metadata.get('related_git_url')
                if git_url:
                    logger.info(f"从关联任务元数据获取git_url: {git_url}")

            if not git_url:
                # 回退到旧逻辑：从相关任务获取git_url
                logger.info(f"任务缺少git_url，尝试从相关任务获取 | related_task_id: {related_task_id}")
                git_url = self._get_git_url_from_related_task(related_task_id)

            if not git_url:
                # 尝试从jobs表获取git_url
                logger.info(f"尝试从jobs表获取git_url | bad_job_id: {task.get('bad_job_id')}")
                git_url = self._get_git_url_from_job(task.get('bad_job_id'))

            if not git_url:
                error_msg = "无法获取Git仓库URL（尝试了task、关联任务、元数据和jobs表）"
                logger.error(f"{error_msg} | ID: {task_id}")
                return {'status': 'failed', 'error': error_msg, 'id': task_id}

            logger.info(f"成功获取git_url: {git_url}")

            # 获取共享仓库目录
            repo_dir, job_dir = self._get_repo_dir(task_id, task['bad_job_id'], git_url)

            try:
                # 获取候选commit的父提交
                parent_commit = self._get_parent_commit(repo_dir, candidate_commit)
                if not parent_commit:
                    error_msg = f"无法获取父提交 | commit: {candidate_commit}"
                    logger.error(f"{error_msg} | ID: {task_id}")
                    return {'status': 'failed', 'error': error_msg, 'id': task_id}

                logger.info(f"父提交获取成功 | 候选: {candidate_commit} | 父提交: {parent_commit}")

                # 并行提交两个单点测试作业
                verification_result = self._submit_parallel_verification_jobs(
                    task, repo_dir, parent_commit, candidate_commit
                )

                if verification_result['status'] == 'success':
                    if verification_result.get('verifiable', False):
                        # 验证成功，进行文件检查（可选，用于提高置信度）
                        file_check_result = None
                        try:
                            error_id = task.get('error_id', '')
                            if error_id:
                                # 获取 commit 修改的文件列表
                                changed_files = self._get_commit_changed_files(repo_dir, candidate_commit)

                                # 检查文件是否在错误日志中被提及
                                file_check_result = self._check_files_mentioned_in_error(error_id, changed_files)

                                # 将文件检查结果添加到 verification_result
                                verification_result['file_check'] = file_check_result

                                if not file_check_result.get('mentioned', False):
                                    logger.warning(
                                        f"文件检查警告 | task_id: {task_id} | "
                                        f"commit 修改的文件未在错误日志中被提及，可能是误报"
                                    )
                            else:
                                logger.debug(f"跳过文件检查：error_id 为空 | task_id: {task_id}")

                        except Exception as e:
                            logger.error(f"文件检查失败: {str(e)} | task_id: {task_id}")
                            logger.error(traceback.format_exc())
                            # 文件检查失败不影响验证流程，继续执行

                        # 验证成功，复用结果（传递 task_metadata 以获取 introduced_errids）
                        return self._handle_verification_success(task, verification_result, task_metadata)
                    else:
                        # 验证失败，边界条件不满足，回退到标准bisect
                        return self._handle_verification_failure(task, verification_result)
                else:
                    # 验证过程失败，回退到标准bisect
                    return self._handle_verification_failure(task, verification_result)

            finally:
                # 释放仓库回池（而不是删除）
                self._release_repo_to_pool(repo_dir, job_dir)

        except Exception as e:
            error_msg = f"验证任务异常: {str(e)}"
            logger.error(f"{error_msg} | ID: {task.get('id', 'unknown')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg, 'id': task.get('id', 'unknown')}

    def _get_task_metadata(self, task: Dict) -> Optional[Dict]:
        """从任务的j字段获取元数据"""
        try:
            j_field = task.get('j', {})
            if isinstance(j_field, str):
                import json
                j_field = json.loads(j_field)

            related_task_id = j_field.get('related_task_id')

            if not related_task_id:
                logger.error(f"任务 {task['id']} 缺少 related_task_id，无法进行验证")
                return None

            # 从关联任务获取完整信息（包括 introduced_errids）
            related_task = self._get_related_task(related_task_id)
            if not related_task:
                logger.error(f"无法获取关联任务 {related_task_id} 的信息")
                return None

            candidate_commit = related_task.get('first_bad_commit')

            if not candidate_commit:
                logger.warning(f"关联任务 {related_task_id} 还没有 first_bad_commit，可能尚未完成 bisect")
                return None

            # 解析关联任务的 j 字段
            related_j = related_task.get('j', {})
            if isinstance(related_j, str):
                related_j = json.loads(related_j) if related_j else {}

            return {
                'candidate_commit': candidate_commit,
                'related_task_id': related_task_id,
                'error_signature': j_field.get('error_signature', ''),
                'related_git_url': related_task.get('git_url'),
                # 新增：从关联任务获取 introduced_errids 等信息
                'introduced_errids': related_j.get('introduced_errids', []),
                'parent_job_id': related_j.get('parent_job_id'),
                'parent_commit': related_j.get('parent_commit')
            }

        except Exception as e:
            logger.error(f"解析任务元数据失败: {str(e)} | task.j: {task.get('j')}")
            return None

    def _get_related_task(self, related_task_id: str) -> Optional[Dict]:
        """获取关联任务的详细信息"""
        try:
            sql_query = f"""
                SELECT id, first_bad_commit, git_url, bisect_status, j
                FROM bisect
                WHERE id = {int(related_task_id)}
                LIMIT 1
            """

            results = self.client.sql_select(sql_query)

            if results and len(results) > 0:
                task = results[0]
                # 检查关联任务是否已完成
                if task.get('bisect_status') != 'success':
                    logger.warning(f"关联任务 {related_task_id} 状态不是 success: {task.get('bisect_status')}")
                    return None
                return task

            logger.error(f"未找到关联任务 {related_task_id}")
            return None

        except Exception as e:
            logger.error(f"获取关联任务失败: {str(e)} | related_task_id: {related_task_id}")
            return None

    def _get_git_url_from_related_task(self, related_task_id: str) -> Optional[str]:
        """从相关任务获取git_url"""
        try:
            if not related_task_id:
                return None

            # 查询相关任务
            sql_query = f"""
                SELECT git_url
                FROM bisect
                WHERE id = {int(related_task_id)}
                LIMIT 1
            """

            results = self.client.sql_select(sql_query)

            if results and len(results) > 0:
                git_url = results[0].get('git_url')
                if git_url:
                    logger.info(f"从相关任务获取到git_url | related_task_id: {related_task_id} | git_url: {git_url}")
                    return git_url

            logger.warning(f"相关任务中未找到git_url | related_task_id: {related_task_id}")
            return None

        except Exception as e:
            logger.error(f"从相关任务获取git_url失败: {str(e)} | related_task_id: {related_task_id}")
            return None

    def _get_git_url_from_job(self, bad_job_id: str) -> Optional[str]:
        """从jobs表获取git_url"""
        try:
            if not bad_job_id:
                return None

            # 查询jobs表获取full_text_kv
            sql_query = f"""
                SELECT full_text_kv
                FROM jobs
                WHERE id = {int(bad_job_id)}
                LIMIT 1
            """

            results = self.client.sql_select(sql_query)

            if results and len(results) > 0:
                full_text_kv = results[0].get('full_text_kv', '')
                if full_text_kv:
                    # 使用共享工具函数提取git_url
                    git_url = extract_git_url_from_full_text_kv(full_text_kv)
                    if git_url:
                        logger.info(f"从jobs表提取到git_url | bad_job_id: {bad_job_id} | git_url: {git_url}")
                        return git_url

            logger.warning(f"jobs表中未找到git_url | bad_job_id: {bad_job_id}")
            return None

        except Exception as e:
            logger.error(f"从jobs表获取git_url失败: {str(e)} | bad_job_id: {bad_job_id}")
            return None

    def _get_repo_dir(self, task_id: str, bad_job_id: str, repo_url: str) -> Tuple[str, str]:
        """获取共享仓库目录"""
        return self.repo_manager.get_repo_dir(task_id, bad_job_id, repo_url)

    def _get_parent_commit(self, repo_dir: str, commit: str) -> Optional[str]:
        """获取提交的父提交"""
        try:
            # 使用git命令获取父提交
            result = subprocess.run(
                ['git', '-C', repo_dir, 'rev-parse', f'{commit}^1'],
                capture_output=True,
                text=True,
                check=True,
                timeout=60  # 60秒超时
            )

            parent_commit = result.stdout.strip()
            if not parent_commit:
                logger.warning(f"提交 {commit} 可能没有父提交（可能是初始提交）")
                return None

            logger.debug(f"父提交获取成功 | commit: {commit} | parent: {parent_commit}")
            return parent_commit

        except subprocess.CalledProcessError as e:
            logger.error(f"获取父提交失败 | commit: {commit} | error: {e.stderr}")
            return None
        except subprocess.TimeoutExpired:
            logger.error(f"获取父提交超时 | commit: {commit}")
            return None
        except Exception as e:
            logger.error(f"获取父提交异常 | commit: {commit} | error: {str(e)}")
            return None

    def _submit_parallel_verification_jobs(self, task: Dict, repo_dir: str,
                                         parent_commit: str, candidate_commit: str) -> Dict:
        """并行提交两个单点测试作业进行边界验证"""
        try:
            task_id = task['id']
            bad_job_id = task['bad_job_id']
            git_url = task['git_url']

            logger.info(f"开始并行验证 | 父提交: {parent_commit} | 候选: {candidate_commit}")

            # 创建两个验证作业
            verification_jobs = [
                {
                    'name': f'verification_parent_{task_id}',
                    'commit': parent_commit,
                    'expected_result': 'good',  # 父提交应该没有该问题
                    'task_id': task_id,
                    'type': 'parent'
                },
                {
                    'name': f'verification_candidate_{task_id}',
                    'commit': candidate_commit,
                    'expected_result': 'bad',   # 候选提交应该有该问题
                    'task_id': task_id,
                    'type': 'candidate'
                }
            ]

            # 并行提交作业
            job_results = {}

            with ThreadPoolExecutor(max_workers=2) as executor:
                future_to_job = {
                    executor.submit(
                        self._submit_single_verification_job,
                        job_info, task, repo_dir
                    ): job_info for job_info in verification_jobs
                }

                for future in as_completed(future_to_job):
                    job_info = future_to_job[future]
                    try:
                        result = future.result(timeout=self.verification_timeout)
                        job_results[job_info['type']] = result
                        logger.info(f"验证作业完成 | type: {job_info['type']} | commit: {job_info['commit']} | result: {result}")
                    except Exception as e:
                        logger.error(f"验证作业异常 | type: {job_info['type']} | error: {str(e)}")
                        job_results[job_info['type']] = {'status': 'error', 'error': str(e)}

            # 分析验证结果
            return self._analyze_verification_results(job_results, parent_commit, candidate_commit)

        except Exception as e:
            logger.error(f"并行验证异常: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def _submit_single_verification_job(self, job_info: Dict, original_task: Dict,
                                      repo_dir: str) -> Dict:
        """提交单个验证作业"""
        try:
            commit = job_info['commit']
            expected_result = job_info['expected_result']
            job_type = job_info['type']

            logger.info(f"提交验证作业 | type: {job_type} | commit: {commit} | expected: {expected_result}")

            # 使用GitBisect系统构建作业配置并提交
            bisect_instance = GitBisect(logger)

            try:
                # 使用原始任务的bad_job_id构建基础作业配置
                bad_job_id = original_task.get('bad_job_id')
                if not bad_job_id:
                    return {'status': 'error', 'error': '缺少bad_job_id'}

                # 构建基础作业配置
                job_config = bisect_instance.init_job_content(bad_job_id)

                # 替换commit为验证目标commit
                if 'ss' in job_config and 'linux' in job_config['ss']:
                    job_config['ss']['linux']['commit'] = commit
                elif 'program' in job_config and 'makepkg' in job_config['program']:
                    job_config['program']['makepkg']['commit'] = commit
                else:
                    return {'status': 'error', 'error': '无法识别的作业结构'}

                # 提交作业
                job_id, result_root, *_ = bisect_instance.submit_job(job_config)
                logger.info(f"作业提交成功 | job_id: {job_id} | type: {job_type} | commit: {commit}")

                # 等待作业完成并获取状态
                error_id = original_task.get('error_id', '')
                status = self._wait_for_job_status(bisect_instance, job_id, error_id, job_type)

                # 构建结果
                job_result = {
                    'status': 'completed',
                    'job_id': job_id,  # 保存 job_id 用于后续 errid diff 计算
                    'test_result': 'passed' if status == 'good' else 'failed',
                    'exit_code': 0 if status == 'good' else 1,
                    'actual_status': status
                }

                logger.info(f"验证作业完成 | job_id: {job_id} | type: {job_type} | commit: {commit} | status: {status}")
                return job_result

            except Exception as e:
                logger.error(f"作业提交或状态检查失败 | type: {job_type} | error: {str(e)}")
                return {'status': 'error', 'error': str(e)}

        except Exception as e:
            logger.error(f"单个验证作业异常 | type: {job_type} | error: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def _wait_for_job_status(self, bisect_instance: GitBisect, job_id: str, error_id: str, job_type: str) -> str:
        """等待作业完成并检查状态"""
        try:
            logger.info(f"等待作业完成 | job_id: {job_id} | type: {job_type}")

            # 使用bisect实例的轮询方法获取作业统计信息
            job_stats, job_health = bisect_instance._poll_job_stats(job_id)

            # 根据作业类型检查状态
            if job_type == 'candidate':
                # 候选提交：必须存在该errid才通过
                has_error = bisect_instance._has_error_id(job_stats, error_id)
                status = 'bad' if has_error else 'good'
                logger.info(f"候选提交验证结果 | commit: {job_id} | has_error: {has_error} | status: {status}")
            else:  # parent
                # 父提交：必须不存在该errid才通过
                has_error = bisect_instance._has_error_id(job_stats, error_id)
                status = 'good' if not has_error else 'bad'
                logger.info(f"父提交验证结果 | commit: {job_id} | has_error: {has_error} | status: {status}")

            return status

        except Exception as e:
            logger.error(f"等待作业状态异常 | job_id: {job_id} | error: {str(e)}")
            return 'skip'

    def _submit_real_job(self, original_task: Dict, commit: str, job_type: str) -> Optional[int]:
        """提交真实作业到调度器API"""
        try:
            # 获取调度器API配置
            sched_host = os.environ.get('SCHED_HOST', 'localhost')
            sched_port = os.environ.get('SCHED_PORT', '3000')
            api_url = f"http://{sched_host}:{sched_port}/scheduler/v1/jobs/submit"

            # 构建验证作业的配置
            job_config = self._build_verification_job_config(original_task, commit, job_type)

            logger.info(f"提交验证作业 | type: {job_type} | commit: {commit} | API: {api_url}")

            # 提交作业到调度器
            response = requests.post(
                api_url,
                json=job_config,
                headers={"Content-Type": "application/json"},
                timeout=30
            )

            if response.status_code == 200:
                result = response.json()
                job_id = result.get('job_id')
                if job_id:
                    logger.info(f"作业提交成功 | job_id: {job_id} | type: {job_type} | commit: {commit}")
                    return int(job_id)
                else:
                    logger.error(f"作业提交成功但未返回job_id | response: {result}")
                    return None
            else:
                logger.error(f"作业提交失败 | status: {response.status_code} | response: {response.text}")
                return None

        except requests.exceptions.RequestException as e:
            logger.error(f"作业提交请求异常: {str(e)}")
            return None
        except Exception as e:
            logger.error(f"作业提交异常: {str(e)}")
            return None

    def _build_verification_job_config(self, original_task: Dict, commit: str, job_type: str) -> Dict:
        """构建验证作业配置"""
        # 获取原始任务的错误ID和相关信息
        error_id = original_task.get('error_id', '')
        bad_job_id = original_task.get('bad_job_id', '')
        git_url = original_task.get('git_url', '')

        # 构建作业名称
        job_name = f"verification_{job_type}_{original_task['id']}_{commit[:8]}"

        # 构建测试参数
        test_params = {
            "suite": "bisect_verification",
            "testcase": "bisect_verification",
            "bisect_verification": "true",
            "verification_task_id": str(original_task['id']),
            "verification_type": job_type,
            "target_commit": commit,
            "original_error_id": error_id,
            "original_bad_job_id": str(bad_job_id),
            "git_url": git_url
        }

        # 如果是父提交验证，期望结果为good
        if job_type == 'parent':
            test_params["expected_result"] = "good"
        else:  # candidate
            test_params["expected_result"] = "bad"

        job_config = {
            "job": {
                "suite": "bisect_verification",
                "testcase": "bisect_verification",
                "submit_job": "bisect_verification",
                "job_name": job_name,
                "params": test_params
            },
            "account": {
                "my_account": os.environ.get('BISECT_ACCOUNT', 'bisect')
            }
        }

        return job_config

    def _wait_for_job_completion(self, job_id: str, commit: str, job_type: str) -> Dict:
        """等待作业完成并获取结果 - 模拟实现"""
        try:
            logger.info(f"等待作业完成 | job_id: {job_id} | commit: {commit} | type: {job_type}")

            # 模拟等待时间
            time.sleep(2)  # 实际实现中需要轮询作业状态

            # 这里应该调用实际的作业查询API来获取结果
            # 为了演示，我们模拟不同的结果场景

            import random

            # 模拟不同的验证结果
            scenarios = [
                {'status': 'completed', 'test_result': 'passed', 'exit_code': 0},     # good commit
                {'status': 'completed', 'test_result': 'failed', 'exit_code': 1},     # bad commit
                {'status': 'completed', 'test_result': 'error', 'exit_code': 2},      # test error
                {'status': 'failed', 'error': 'Job execution failed'},                 # job failure
            ]

            # 根据作业类型选择合适的结果
            if job_type == 'parent':
                # 父提交应该没有该问题 (good)
                result = random.choice([
                    {'status': 'completed', 'test_result': 'passed', 'exit_code': 0},
                    {'status': 'completed', 'test_result': 'failed', 'exit_code': 1},  # 误判情况
                    {'status': 'failed', 'error': 'Job execution failed'}
                ])
            else:  # candidate
                # 候选提交应该有该问题 (bad)
                result = random.choice([
                    {'status': 'completed', 'test_result': 'failed', 'exit_code': 1},
                    {'status': 'completed', 'test_result': 'passed', 'exit_code': 0},   # 误判情况
                    {'status': 'failed', 'error': 'Job execution failed'}
                ])

            logger.info(f"作业完成 | job_id: {job_id} | result: {result}")
            return result

        except Exception as e:
            logger.error(f"等待作业完成异常 | job_id: {job_id} | error: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def _analyze_verification_results(self, job_results: Dict, parent_commit: str, candidate_commit: str) -> Dict:
        """分析验证结果"""
        try:
            parent_result = job_results.get('parent', {})
            candidate_result = job_results.get('candidate', {})

            logger.info(f"分析验证结果 | parent: {parent_result} | candidate: {candidate_result}")

            # 提取 job_id（用于后续 errid diff 计算）
            parent_job_id = parent_result.get('job_id')
            candidate_job_id = candidate_result.get('job_id')

            # 检查是否有作业失败
            if parent_result.get('status') != 'completed' or candidate_result.get('status') != 'completed':
                error_msg = f"验证作业执行失败 | parent_status: {parent_result.get('status')} | candidate_status: {candidate_result.get('status')}"
                logger.error(error_msg)
                return {'status': 'failed', 'error': error_msg}

            # 检查实际状态是否符合验证条件
            parent_status = parent_result.get('actual_status')
            candidate_status = candidate_result.get('actual_status')

            logger.info(f"验证状态分析 | parent_status: {parent_status} | candidate_status: {candidate_status}")

            # 验证成功的条件：
            # 1. 父提交状态为good（不存在该errid）
            # 2. 候选提交状态为bad（存在该errid）
            if parent_status == 'good' and candidate_status == 'bad':
                logger.info("边界验证成功 | 可以复用候选commit结果")
                return {
                    'status': 'success',
                    'verifiable': True,
                    'parent_commit': parent_commit,
                    'candidate_commit': candidate_commit,
                    'parent_job_id': parent_job_id,        # 新增：父提交作业ID
                    'candidate_job_id': candidate_job_id,  # 新增：候选提交作业ID
                    'verification_details': {
                        'parent_status': parent_status,
                        'candidate_status': candidate_status,
                        'parent_test_result': parent_result.get('test_result'),
                        'candidate_test_result': candidate_result.get('test_result'),
                        'parent_exit_code': parent_result.get('exit_code'),
                        'candidate_exit_code': candidate_result.get('exit_code')
                    }
                }
            else:
                # 验证失败，边界条件不满足
                reason = f"边界条件不满足: parent_status={parent_status}, candidate_status={candidate_status}"
                logger.warning(f"边界验证失败 | {reason}")
                return {
                    'status': 'success',
                    'verifiable': False,
                    'parent_commit': parent_commit,
                    'candidate_commit': candidate_commit,
                    'parent_job_id': parent_job_id,        # 新增：即使验证失败也保存
                    'candidate_job_id': candidate_job_id,  # 新增：即使验证失败也保存
                    'reason': reason,
                    'verification_details': {
                        'parent_status': parent_status,
                        'candidate_status': candidate_status,
                        'parent_test_result': parent_result.get('test_result'),
                        'candidate_test_result': candidate_result.get('test_result'),
                        'parent_exit_code': parent_result.get('exit_code'),
                        'candidate_exit_code': candidate_result.get('exit_code')
                    }
                }

        except Exception as e:
            logger.error(f"验证结果分析异常: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def _handle_verification_success(self, task: Dict, verification_result: Dict, task_metadata: Dict) -> Dict:
        """处理验证成功的情况 - 复用结果（优先使用关联任务的 introduced_errids）"""
        try:
            task_id = task['id']
            candidate_commit = verification_result['candidate_commit']
            parent_commit = verification_result.get('parent_commit')
            parent_job_id = verification_result.get('parent_job_id')
            candidate_job_id = verification_result.get('candidate_job_id')

            logger.info(f"验证成功，复用结果 | ID: {task_id} | first_bad_commit: {candidate_commit}")
            logger.info(f"验证作业 | parent_job: {parent_job_id} | candidate_job: {candidate_job_id}")

            # 优先使用关联任务已保存的 introduced_errids
            introduced_errids = task_metadata.get('introduced_errids', [])

            # 如果关联任务没有 introduced_errids，尝试重新计算
            if not introduced_errids and parent_job_id and candidate_job_id:
                try:
                    logger.warning(f"关联任务没有 introduced_errids，重新计算 | parent: {parent_job_id} | candidate: {candidate_job_id}")
                    introduced_errids = self.calculate_errid_diff(parent_job_id, candidate_job_id)
                    logger.info(f"重新计算得到 introduced_errids: {len(introduced_errids)} 个")
                    if introduced_errids and len(introduced_errids) <= 5:
                        logger.info(f"  Sample: {introduced_errids[:5]}")
                except Exception as e:
                    logger.error(f"计算 errid diff 失败: {str(e)} | 将继续但无法进行 HEAD 检测")
                    logger.error(traceback.format_exc())
            else:
                logger.info(f"使用关联任务的 introduced_errids: {len(introduced_errids)} 个")

            # 更新任务状态为success，并记录复用的commit和job_id
            current_time = int(time.time())

            # 构造 j 字段
            j_field = {
                "verification_status": "verified",  # 改为 'verified' 以便 HeadValidator 扫描
                "verification_details": verification_result.get('verification_details', {}),
                "result_source": "reused",  # 标记结果来源为复用
                "verification_parent_commit": parent_commit,
                "verification_candidate_commit": candidate_commit,
                "verification_parent_job_id": parent_job_id,
                "verification_candidate_job_id": candidate_job_id,
                "verification_passed": True,
                "result_reused_from": task_metadata.get('related_task_id'),
                "introduced_errids": introduced_errids,  # 保存 introduced_errids
                "introduced_errids_count": len(introduced_errids)
            }

            # 添加文件检查结果（如果有）
            file_check_result = verification_result.get('file_check')
            if file_check_result:
                j_field['file_check_result'] = file_check_result
                logger.info(
                    f"文件检查结果已保存 | task_id: {task_id} | "
                    f"mentioned: {file_check_result.get('mentioned', False)} | "
                    f"ratio: {file_check_result.get('mention_ratio', 0):.1%}"
                )

            # 计算置信度
            confidence_level = self._calculate_confidence_level(file_check_result)
            j_field['confidence_level'] = confidence_level

            if confidence_level == 'low':
                logger.warning(
                    f"低置信度 bisect 结果 | task_id: {task_id} | "
                    f"mention_ratio: {file_check_result.get('mention_ratio', 0) if file_check_result else 0:.1%} | "
                    f"可能是误报，建议人工审核"
                )
            elif confidence_level == 'medium':
                logger.info(
                    f"中等置信度 bisect 结果 | task_id: {task_id} | "
                    f"mention_ratio: {file_check_result.get('mention_ratio', 0) if file_check_result else 0:.1%} | "
                    f"建议人工审核"
                )

            success_doc = {
                "bisect_status": "success",
                "first_bad_commit": candidate_commit,
                "updated_at": current_time,
                "end_time": current_time,
                "start_time": current_time - 300,  # 假设验证耗时5分钟
                "last_error": "",  # 清空之前的错误信息
                "confidence_level": confidence_level,  # 新增置信度字段
                "j": j_field
            }

            # 更新数据库
            update_result = self.client.update("bisect", task_id, success_doc)
            if update_result:
                logger.info(f"任务状态更新成功 | ID: {task_id} | status: success | source: reused | introduced_errids: {len(introduced_errids)}")

                # 写入 regression 记录（只有验证通过的结果才写入）
                try:
                    write_success = write_regression_record(self.client, task, candidate_commit)
                    if write_success:
                        logger.info(f"Regression 记录已写入 | task_id: {task_id} | error_id: {task.get('error_id')}")
                    else:
                        logger.warning(f"Regression 记录写入失败 | task_id: {task_id}")
                except Exception as e:
                    logger.error(f"Regression 写入异常 | task_id: {task_id} | error: {str(e)}")

                # 注意：bisect 成功报告的生成已移至 HEAD validator
                # 在 HEAD 检查完成后统一生成，包含完整的 HEAD 状态信息
                # 这样可以避免重复生成报告，并确保报告包含最新的 HEAD 验证结果

                return {
                    'status': 'success',
                    'id': task_id,
                    'first_bad_commit': candidate_commit,
                    'result_source': 'reused',
                    'verification_passed': True,
                    'parent_job_id': parent_job_id,
                    'candidate_job_id': candidate_job_id,
                    'introduced_errids': introduced_errids
                }
            else:
                error_msg = "数据库更新失败"
                logger.error(f"{error_msg} | ID: {task_id}")
                return {'status': 'failed', 'error': error_msg, 'id': task_id}

        except Exception as e:
            error_msg = f"验证成功处理异常: {str(e)}"
            logger.error(f"{error_msg} | ID: {task.get('id', 'unknown')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg, 'id': task.get('id', 'unknown')}

    def _handle_verification_failure(self, task: Dict, verification_result: Dict) -> Dict:
        """处理验证失败的情况 - 根据失败原因决定是标记为不可验证还是重试"""
        try:
            task_id = task['id']
            reason = verification_result.get('reason', '边界验证失败')

            # 判断失败原因是否为边界条件不满足（flaky test或bisect错误）
            if "边界条件不满足" in reason:
                # 这种情况表示parent=good, candidate=good，可能是flaky test或bisect错误
                # 不应该重新bisect，而是标记为不可验证，需要人工审核
                logger.warning(f"验证失败：边界条件不满足 | ID: {task_id} | 标记为不可验证")

                current_time = int(time.time())
                unverifiable_doc = {
                    "bisect_status": "unverifiable",
                    "updated_at": current_time,
                    "j": {
                        "verification_status": "unverifiable",
                        "verification_failure_reason": reason,
                        "verification_details": verification_result.get('verification_details', {}),
                        "verification_attempted": True,
                        "verification_passed": False,
                        "requires_manual_review": True,
                        "unverifiable_reason": "边界条件不满足（可能是flaky test或bisect错误）"
                    }
                }

                # 更新数据库
                update_result = self.client.update("bisect", task_id, unverifiable_doc)
                if update_result:
                    logger.info(f"任务标记为不可验证 | ID: {task_id} | 需要人工审核")

                    # 写入通知文件
                    try:
                        # 获取 j 字段以提取 change_point（完整的 commit 信息）
                        j_field = task.get('j', {})
                        if isinstance(j_field, str):
                            try:
                                import json
                                j_field = json.loads(j_field) if j_field else {}
                            except:
                                j_field = {}

                        # 优先使用 change_point，否则组合 first_bad_commit + subject
                        first_bad_commit_display = j_field.get('change_point')
                        if not first_bad_commit_display:
                            first_bad_commit = task.get('first_bad_commit', 'N/A')
                            subject = j_field.get('first_bad_commit_subject', '')
                            if subject:
                                first_bad_commit_display = f"{first_bad_commit} {subject}"
                            else:
                                first_bad_commit_display = first_bad_commit

                        self.notification_writer.write_verification_failed_alert(
                            task_id=task_id,
                            error_id=task.get('error_id', 'unknown'),
                            first_bad_commit=first_bad_commit_display,
                            git_url=task.get('git_url', 'N/A'),
                            failure_reason=reason,
                            extra_info={
                                'unverifiable': True,
                                'requires_manual_review': True,
                                'verification_details': verification_result.get('verification_details', {})
                            }
                        )
                        logger.info(f"不可验证任务通知已写入文件 | task_id: {task_id}")
                    except Exception as e:
                        logger.error(f"写入不可验证任务通知异常 | task_id: {task_id} | error: {str(e)}")

                    return {
                        'status': 'success',
                        'id': task_id,
                        'verification_passed': False,
                        'unverifiable': True
                    }
                else:
                    error_msg = "数据库更新失败"
                    logger.error(f"{error_msg} | ID: {task_id}")
                    return {'status': 'failed', 'error': error_msg, 'id': task_id}

            else:
                # 其他失败原因（超时、系统错误等），可以考虑重试或回退到标准bisect
                logger.info(f"验证失败，回退到标准bisect | ID: {task_id} | reason: {reason}")

                # 更新任务状态为wait，让标准bisect消费者处理
                current_time = int(time.time())
                reset_doc = {
                    "bisect_status": "wait",
                    "updated_at": current_time,
                    "j": {
                        "verification_status": "failed",
                        "verification_failure_reason": reason,
                        "verification_details": verification_result.get('verification_details', {}),
                        "verification_attempted": True,
                        "verification_passed": False,
                        "fallback_to_standard_bisect": True
                    }
                }

                # 更新数据库
                update_result = self.client.update("bisect", task_id, reset_doc)
                if update_result:
                    logger.info(f"任务状态重置成功 | ID: {task_id} | status: wait | fallback: standard_bisect")
                    return {
                        'status': 'success',
                        'id': task_id,
                        'verification_passed': False,
                        'fallback_to_standard_bisect': True
                    }
                else:
                    error_msg = "数据库更新失败"
                    logger.error(f"{error_msg} | ID: {task_id}")
                    return {'status': 'failed', 'error': error_msg, 'id': task_id}

        except Exception as e:
            error_msg = f"验证失败处理异常: {str(e)}"
            logger.error(f"{error_msg} | ID: {task.get('id', 'unknown')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg, 'id': task.get('id', 'unknown')}

    def _release_repo_to_pool(self, repo_dir: str, job_dir: str):
        """释放仓库回池（如果失败则回退到删除）"""
        try:
            if os.path.exists(repo_dir):
                # 尝试释放回池
                self.repo_manager.release_repo_dir(repo_dir)
                logger.info(f"仓库已释放回池: {repo_dir}")
        except Exception as e:
            # 如果释放失败，回退到删除
            logger.warning(f"释放仓库回池失败，回退到删除: {str(e)} | path: {repo_dir}")
            self._cleanup_repo_dir(job_dir)

    def _cleanup_repo_dir(self, job_dir: str):
        """清理仓库目录（仅在池化释放失败时使用）"""
        try:
            if os.path.exists(job_dir):
                import shutil
                shutil.rmtree(job_dir, ignore_errors=True)
                logger.debug(f"仓库目录清理完成: {job_dir}")
        except Exception as e:
            logger.error(f"清理仓库目录失败: {str(e)} | path: {job_dir}")

    def get_all_errids_from_job(self, job_id: str) -> List[str]:
        """
        从作业中提取所有 errid

        Args:
            job_id: 作业ID

        Returns:
            errid 列表
        """
        try:
            if not job_id:
                logger.warning("job_id is empty, cannot extract errids")
                return []

            logger.info(f"提取 errid | job_id: {job_id}")

            # 使用 GitBisect 的 _poll_job_stats 方法获取作业统计信息
            bisect_instance = GitBisect(logger)
            job_stats, _ = bisect_instance._poll_job_stats(job_id)

            if not job_stats:
                logger.warning(f"No stats found for job {job_id}")
                return []

            # stats 是字典，所有 keys 就是 errids
            errids = list(job_stats.keys())
            logger.info(f"Extracted {len(errids)} errids from job {job_id}")

            # 记录前几个 errid 用于调试
            if errids:
                logger.debug(f"Sample errids: {errids[:3]}...")

            return errids

        except Exception as e:
            logger.error(f"Failed to extract errids from job {job_id}: {str(e)}")
            logger.error(traceback.format_exc())
            return []

    def calculate_errid_diff(self, parent_job_id: str, bad_job_id: str) -> List[str]:
        """
        计算 errid 差集：bad_job 引入的新 errid

        Args:
            parent_job_id: 父提交的作业ID
            bad_job_id: 候选提交（bad commit）的作业ID

        Returns:
            引入的 errid 列表（在 bad_job 中存在但在 parent_job 中不存在的 errid）
        """
        try:
            logger.info(f"计算 errid diff | parent_job: {parent_job_id} | bad_job: {bad_job_id}")

            # 获取两个作业的 errids
            parent_errids = self.get_all_errids_from_job(parent_job_id)
            bad_errids = self.get_all_errids_from_job(bad_job_id)

            # 计算差集：bad_job 中有但 parent_job 中没有的 errid
            parent_set = set(parent_errids)
            bad_set = set(bad_errids)
            introduced_errids = list(bad_set - parent_set)

            logger.info(
                f"errid diff 结果 | "
                f"parent: {len(parent_errids)} errids | "
                f"bad: {len(bad_errids)} errids | "
                f"introduced: {len(introduced_errids)} errids"
            )

            if introduced_errids:
                # 只显示前5个，避免日志过长
                sample_count = min(5, len(introduced_errids))
                logger.info(f"Introduced errids (showing {sample_count}/{len(introduced_errids)}): {introduced_errids[:sample_count]}")
            else:
                logger.warning("No new errids introduced by bad_commit (possibly a false positive)")

            return introduced_errids

        except Exception as e:
            logger.error(f"Failed to calculate errid diff: {str(e)}")
            logger.error(traceback.format_exc())
            return []

    def _get_commit_changed_files(self, repo_dir: str, commit: str) -> List[str]:
        """
        获取 commit 修改的文件列表

        Args:
            repo_dir: Git 仓库目录
            commit: commit hash

        Returns:
            修改的文件路径列表
        """
        try:
            logger.debug(f"获取 commit 修改的文件 | commit: {commit[:12]}")

            # 使用 git show --name-only 获取修改的文件列表
            result = subprocess.run(
                ['git', '-C', repo_dir, 'show', '--name-only', '--format=', commit],
                capture_output=True,
                text=True,
                check=True,
                timeout=60
            )

            # 过滤空行
            files = [f.strip() for f in result.stdout.split('\n') if f.strip()]

            logger.info(f"commit {commit[:12]} 修改了 {len(files)} 个文件")
            if files and len(files) <= 10:
                logger.debug(f"  修改的文件: {files}")
            elif files:
                logger.debug(f"  修改的文件（前10个）: {files[:10]}")

            return files

        except subprocess.CalledProcessError as e:
            logger.error(f"获取 commit 文件列表失败 | commit: {commit[:12]} | error: {e.stderr}")
            return []
        except subprocess.TimeoutExpired:
            logger.error(f"获取 commit 文件列表超时 | commit: {commit[:12]}")
            return []
        except Exception as e:
            logger.error(f"获取 commit 文件列表异常 | commit: {commit[:12]} | error: {str(e)}")
            return []

    def _check_files_mentioned_in_error(self, error_id: str, changed_files: List[str]) -> Dict[str, Any]:
        """
        检查修改的文件是否在错误日志中被提及

        Args:
            error_id: 错误ID
            changed_files: 修改的文件列表

        Returns:
            检查结果字典：
            {
                'mentioned': bool,  # 是否有文件被提及
                'mentioned_files': List[str],  # 被提及的文件列表
                'total_files': int  # 总文件数
            }
        """
        try:
            if not changed_files:
                logger.warning("changed_files 为空，无法检查文件提及")
                return {
                    'mentioned': False,
                    'mentioned_files': [],
                    'total_files': 0,
                    'reason': 'no_changed_files'
                }

            logger.debug(f"检查文件是否被提及 | error_id: {error_id[:80]} | files: {len(changed_files)}")

            # 从 error_id 中提取可能包含的文件路径
            # error_id 通常是错误日志的签名，可能包含文件路径
            mentioned_files = []

            for file_path in changed_files:
                # 获取文件名（不含路径）
                file_name = os.path.basename(file_path)

                # 检查文件名或路径是否在 error_id 中出现
                if file_name in error_id or file_path in error_id:
                    mentioned_files.append(file_path)
                    logger.debug(f"  文件被提及: {file_path}")

            mentioned = len(mentioned_files) > 0

            logger.info(
                f"文件提及检查结果 | "
                f"total: {len(changed_files)} | "
                f"mentioned: {len(mentioned_files)} | "
                f"ratio: {len(mentioned_files)/len(changed_files):.1%}"
            )

            if mentioned:
                logger.info(f"  被提及的文件: {mentioned_files[:5]}")
            else:
                logger.warning(f"  警告：没有任何修改的文件在错误日志中被提及！可能是误报")

            return {
                'mentioned': mentioned,
                'mentioned_files': mentioned_files,
                'total_files': len(changed_files),
                'mention_ratio': len(mentioned_files) / len(changed_files) if changed_files else 0
            }

        except Exception as e:
            logger.error(f"检查文件提及失败: {str(e)}")
            logger.error(traceback.format_exc())
            return {
                'mentioned': False,
                'mentioned_files': [],
                'total_files': len(changed_files),
                'error': str(e)
            }

    def _calculate_confidence_level(self, file_check_result: Dict) -> str:
        """
        计算 bisect 结果的置信度

        Args:
            file_check_result: 文件检查结果

        Returns:
            'high', 'medium', 'low', 'unknown'
        """
        if not file_check_result:
            return 'unknown'

        mention_ratio = file_check_result.get('mention_ratio', 0)

        if mention_ratio >= 0.5:
            return 'high'
        elif mention_ratio >= 0.1:
            return 'medium'
        else:
            return 'low'


def create_verification_consumer(config: Dict) -> VerificationConsumer:
    """创建验证消费者实例"""
    client = ManticoreClient(
        host=config.get('manticore_host', 'localhost'),
        port=int(config.get('manticore_http_port', '9308'))
    )
    return VerificationConsumer(client, config)
