#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
TaskOptimizer - 任务优化服务

这个模块实现了基于已验证任务结果的新任务优化机制，
通过匹配 introduced_errids 来避免重复 bisect。

功能：
1. 扫描 bisect_status='wait' 的待处理任务
2. 匹配已验证任务的 introduced_errids
3. 应用优化策略（复用结果、快速验证、降优先级）
4. 减少重复 bisect 操作
"""

import os
import sys
import time
import traceback
import json
from typing import Dict, Any, Optional, List

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger

sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from manticore_simple import ManticoreClient


class TaskOptimizer:
    """
    任务优化服务

    利用已验证任务的 introduced_errids 信息，
    优化待处理任务，避免重复 bisect
    """

    def __init__(self, client: ManticoreClient, config: Dict):
        """初始化任务优化服务"""
        self.client = client
        self.config = config

        # 配置参数
        self.optimize_batch_size = config.get('optimize_batch_size', 20)
        self.optimize_interval = config.get('optimize_interval', 1800)  # 默认30分钟
        self.optimization_strategy = config.get('optimization_strategy', 'reuse')  # reuse / verify / priority

        logger.info(
            f"TaskOptimizer initialized | "
            f"batch_size: {self.optimize_batch_size} | "
            f"strategy: {self.optimization_strategy}"
        )

    def scan_pending_tasks(self, limit: int = None) -> List[Dict]:
        """
        扫描待处理任务

        Args:
            limit: 返回的最大任务数

        Returns:
            待处理的任务列表
        """
        try:
            batch_size = limit or self.optimize_batch_size

            # 查询条件：
            # 1. bisect_status = 'wait'
            # 2. error_id 存在（错误 bisect 任务）
            # 3. j.optimized != true（未被优化过）
            sql_query = f"""
                SELECT * FROM bisect
                WHERE bisect_status = 'wait'
                AND error_id != ''
                AND (j.optimized IS NULL OR j.optimized != true)
                ORDER BY priority_level DESC, updated_at ASC
                LIMIT {batch_size}
            """

            logger.info(f"扫描待处理任务 | batch_size: {batch_size}")
            results = self.client.sql_select(sql_query)

            if results:
                logger.info(f"发现 {len(results)} 个待优化任务")
            else:
                logger.info("未发现待优化任务")

            return results or []

        except Exception as e:
            logger.error(f"扫描待处理任务失败: {str(e)}")
            logger.error(traceback.format_exc())
            return []

    def find_matching_verified_tasks(self, new_task: Dict) -> List[Dict]:
        """
        查找匹配的已验证任务

        Args:
            new_task: 新任务记录

        Returns:
            匹配的已验证任务列表
        """
        try:
            error_id = new_task.get('error_id')
            git_url = new_task.get('git_url')

            if not error_id or not git_url:
                logger.debug(f"任务缺少 error_id 或 git_url | task_id: {new_task['id']}")
                return []

            # 查询条件：
            # 1. j.verification_status = 'verified'
            # 2. git_url 相同
            # 3. j.introduced_errids 包含该 error_id
            # 注意：Manticore 的 JSON 字段查询语法可能有限制，这里用简化方式
            sql_query = f"""
                SELECT * FROM bisect
                WHERE j.verification_status = 'verified'
                AND git_url = '{git_url}'
                AND j.introduced_errids IS NOT NULL
                ORDER BY verified_at DESC
                LIMIT 10
            """

            logger.debug(f"查找匹配任务 | error_id: {error_id} | git_url: {git_url}")
            results = self.client.sql_select(sql_query)

            if not results:
                return []

            # 过滤：检查 introduced_errids 是否包含该 error_id
            matched_tasks = []
            for task in results:
                j_field = task.get('j', {})
                if isinstance(j_field, str):
                    j_field = json.loads(j_field)

                introduced_errids = j_field.get('introduced_errids', [])

                # 检查 error_id 是否在 introduced_errids 中
                if error_id in introduced_errids:
                    matched_tasks.append(task)
                    logger.info(
                        f"找到匹配任务 | "
                        f"new_task: {new_task['id']} | "
                        f"verified_task: {task['id']} | "
                        f"first_bad_commit: {task.get('first_bad_commit', 'N/A')[:8]}"
                    )

            return matched_tasks

        except Exception as e:
            logger.error(f"查找匹配任务失败: {str(e)} | task_id: {new_task.get('id')}")
            logger.error(traceback.format_exc())
            return []

    def optimize_task(self, task: Dict, matched_verified_task: Dict) -> Dict:
        """
        优化单个任务

        Args:
            task: 待优化任务
            matched_verified_task: 匹配的已验证任务

        Returns:
            优化结果字典
        """
        try:
            task_id = task['id']
            verified_task_id = matched_verified_task['id']
            first_bad_commit = matched_verified_task.get('first_bad_commit')

            logger.info(
                f"优化任务 | task_id: {task_id} | "
                f"matched: {verified_task_id} | "
                f"strategy: {self.optimization_strategy}"
            )

            if self.optimization_strategy == 'reuse':
                # 策略1：直接复用 first_bad_commit
                return self._apply_reuse_strategy(task_id, verified_task_id, first_bad_commit)

            elif self.optimization_strategy == 'verify':
                # 策略2：设置为 pending_verification（快速验证）
                return self._apply_verify_strategy(task_id, verified_task_id, first_bad_commit)

            elif self.optimization_strategy == 'priority':
                # 策略3：降低优先级（让其他任务先执行）
                return self._apply_priority_strategy(task_id, verified_task_id)

            else:
                error_msg = f"unknown_optimization_strategy: {self.optimization_strategy}"
                logger.error(error_msg)
                return {'status': 'failed', 'error': error_msg}

        except Exception as e:
            error_msg = f"optimize_task_exception: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task.get('id')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg}

    def _apply_reuse_strategy(self, task_id: int, verified_task_id: int, first_bad_commit: str) -> Dict:
        """
        策略1：直接复用 first_bad_commit

        Args:
            task_id: 待优化任务ID
            verified_task_id: 匹配的已验证任务ID
            first_bad_commit: 复用的 first_bad_commit

        Returns:
            优化结果
        """
        try:
            current_time = int(time.time())

            update_doc = {
                "bisect_status": "success",
                "first_bad_commit": first_bad_commit,
                "updated_at": current_time,
                "end_time": current_time,
                "start_time": current_time,
                "j": {
                    "optimized": True,
                    "optimization_strategy": "reuse",
                    "optimization_source_task": verified_task_id,
                    "optimized_at": current_time,
                    "result_source": "optimized_reuse"
                }
            }

            update_result = self.client.update("bisect", task_id, update_doc)

            if update_result:
                logger.info(
                    f"任务优化成功（复用） | "
                    f"task_id: {task_id} | "
                    f"first_bad_commit: {first_bad_commit[:8]}"
                )
                return {
                    'status': 'success',
                    'strategy': 'reuse',
                    'task_id': task_id
                }
            else:
                error_msg = "database_update_failed"
                logger.error(f"{error_msg} | task_id: {task_id}")
                return {'status': 'failed', 'error': error_msg}

        except Exception as e:
            error_msg = f"apply_reuse_strategy_failed: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task_id}")
            return {'status': 'failed', 'error': error_msg}

    def _apply_verify_strategy(self, task_id: int, verified_task_id: int, first_bad_commit: str) -> Dict:
        """
        策略2：设置为 pending_verification（快速验证）

        Args:
            task_id: 待优化任务ID
            verified_task_id: 匹配的已验证任务ID
            first_bad_commit: 候选 first_bad_commit

        Returns:
            优化结果
        """
        try:
            current_time = int(time.time())

            update_doc = {
                "bisect_status": "pending_verification",
                "updated_at": current_time,
                "j": {
                    "expected_commit": first_bad_commit,
                    "related_task_id": verified_task_id,
                    "optimized": True,
                    "optimization_strategy": "verify",
                    "optimization_source_task": verified_task_id,
                    "optimized_at": current_time
                }
            }

            update_result = self.client.update("bisect", task_id, update_doc)

            if update_result:
                logger.info(
                    f"任务优化成功（快速验证） | "
                    f"task_id: {task_id} | "
                    f"candidate: {first_bad_commit[:8]}"
                )
                return {
                    'status': 'success',
                    'strategy': 'verify',
                    'task_id': task_id
                }
            else:
                error_msg = "database_update_failed"
                logger.error(f"{error_msg} | task_id: {task_id}")
                return {'status': 'failed', 'error': error_msg}

        except Exception as e:
            error_msg = f"apply_verify_strategy_failed: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task_id}")
            return {'status': 'failed', 'error': error_msg}

    def _apply_priority_strategy(self, task_id: int, verified_task_id: int) -> Dict:
        """
        策略3：降低优先级

        Args:
            task_id: 待优化任务ID
            verified_task_id: 匹配的已验证任务ID

        Returns:
            优化结果
        """
        try:
            current_time = int(time.time())

            # 降低优先级（假设优先级范围 1-10，降低到 1）
            update_doc = {
                "priority_level": 1,
                "updated_at": current_time,
                "j": {
                    "optimized": True,
                    "optimization_strategy": "priority",
                    "optimization_source_task": verified_task_id,
                    "optimized_at": current_time,
                    "priority_reason": "similar_task_exists"
                }
            }

            update_result = self.client.update("bisect", task_id, update_doc)

            if update_result:
                logger.info(f"任务优化成功（降优先级） | task_id: {task_id}")
                return {
                    'status': 'success',
                    'strategy': 'priority',
                    'task_id': task_id
                }
            else:
                error_msg = "database_update_failed"
                logger.error(f"{error_msg} | task_id: {task_id}")
                return {'status': 'failed', 'error': error_msg}

        except Exception as e:
            error_msg = f"apply_priority_strategy_failed: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task_id}")
            return {'status': 'failed', 'error': error_msg}

    def run_optimization_cycle(self) -> Dict[str, int]:
        """
        运行一次优化周期

        Returns:
            统计信息字典
        """
        try:
            logger.info("=" * 60)
            logger.info("开始任务优化周期")
            logger.info("=" * 60)

            # 扫描待处理任务
            pending_tasks = self.scan_pending_tasks()

            if not pending_tasks:
                logger.info("本周期无待优化任务")
                return {
                    'scanned': 0,
                    'optimized': 0,
                    'no_match': 0,
                    'failed': 0
                }

            # 优化统计
            stats = {
                'scanned': len(pending_tasks),
                'optimized': 0,
                'no_match': 0,
                'failed': 0
            }

            # 逐个优化任务
            for task in pending_tasks:
                try:
                    # 查找匹配的已验证任务
                    matched_tasks = self.find_matching_verified_tasks(task)

                    if not matched_tasks:
                        logger.debug(f"未找到匹配任务 | task_id: {task['id']}")
                        stats['no_match'] += 1
                        continue

                    # 使用第一个匹配任务进行优化
                    best_match = matched_tasks[0]
                    result = self.optimize_task(task, best_match)

                    if result.get('status') == 'success':
                        stats['optimized'] += 1
                    else:
                        stats['failed'] += 1

                except Exception as e:
                    logger.error(f"优化任务异常: {str(e)} | task_id: {task.get('id')}")
                    stats['failed'] += 1

            # 输出统计信息
            logger.info("=" * 60)
            logger.info(
                f"优化周期完成 | "
                f"扫描: {stats['scanned']} | "
                f"优化: {stats['optimized']} | "
                f"无匹配: {stats['no_match']} | "
                f"失败: {stats['failed']}"
            )
            logger.info("=" * 60)

            return stats

        except Exception as e:
            logger.error(f"优化周期异常: {str(e)}")
            logger.error(traceback.format_exc())
            return {
                'scanned': 0,
                'optimized': 0,
                'no_match': 0,
                'failed': 0,
                'error': str(e)
            }


def create_task_optimizer(config: Dict) -> TaskOptimizer:
    """创建任务优化服务实例"""
    client = ManticoreClient(
        host=config.get('manticore_host', 'localhost'),
        port=int(config.get('manticore_http_port', '9308'))
    )
    return TaskOptimizer(client, config)


if __name__ == '__main__':
    """测试任务优化服务"""
    # 配置
    config = {
        'manticore_host': os.environ.get('MANTICORE_HOST', 'localhost'),
        'manticore_http_port': os.environ.get('MANTICORE_HTTP_PORT', '9308'),
        'optimize_batch_size': 20,
        'optimize_interval': 1800,
        'optimization_strategy': 'verify'  # reuse / verify / priority
    }

    # 创建优化服务
    optimizer = create_task_optimizer(config)

    # 运行一次优化周期
    stats = optimizer.run_optimization_cycle()

    logger.info(f"优化完成 | 统计: {stats}")
