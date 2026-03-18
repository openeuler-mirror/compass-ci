#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Task optimizer service.

This module scans pending tasks and tries to optimize duplicate work by
matching each task against previously verified tasks via introduced_errids.
"""

import os
import sys
import time
import traceback
import json
from typing import Dict, List

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger

sys.path.append((os.environ['LKP_SRC']) + '/sbin/bisect/')
from lkp_bisect.db.manticore import ManticoreClient


class TaskOptimizer:
    """Optimize duplicate-prone pending tasks based on verified history."""

    def __init__(self, client: ManticoreClient, config: Dict):
        """Initialize optimizer settings."""
        self.client = client
        self.config = config

        self.optimize_batch_size = config.get('optimize_batch_size', 20)
        self.optimize_interval = config.get('optimize_interval', 1800)  # 30 minutes
        self.optimization_strategy = config.get('optimization_strategy', 'reuse')  # reuse / verify / priority

        logger.info(
            "TaskOptimizer initialized | "
            f"batch_size: {self.optimize_batch_size} | "
            f"strategy: {self.optimization_strategy}"
        )

    def scan_pending_tasks(self, limit: int = None) -> List[Dict]:
        """Scan wait-state tasks eligible for optimization."""
        try:
            batch_size = limit or self.optimize_batch_size

            sql_query = f"""
                SELECT * FROM bisect
                WHERE bisect_status = 'wait'
                AND error_id != ''
                AND (j.optimized IS NULL OR j.optimized != true)
                ORDER BY priority_level DESC, updated_at ASC
                LIMIT {batch_size}
            """

            logger.info(f"Scan pending tasks | batch_size: {batch_size}")
            results = self.client.sql_select(sql_query)

            if results:
                logger.info(f"Pending tasks found | count: {len(results)}")
            else:
                logger.info("No pending tasks found")

            return results or []

        except Exception as e:
            logger.error(f"Scan pending tasks failed: {str(e)}")
            logger.error(traceback.format_exc())
            return []

    def find_matching_verified_tasks(self, new_task: Dict) -> List[Dict]:
        """Find verified tasks in the same repo that contain the same error_id."""
        try:
            error_id = new_task.get('error_id')
            git_url = new_task.get('git_url')

            if not error_id or not git_url:
                logger.debug(f"Task missing error_id or git_url | task_id: {new_task['id']}")
                return []

            sql_query = f"""
                SELECT * FROM bisect
                WHERE j.verification_status = 'verified'
                AND git_url = '{git_url}'
                AND j.introduced_errids IS NOT NULL
                ORDER BY verified_at DESC
                LIMIT 10
            """

            logger.debug(f"Find matches | error_id: {error_id} | git_url: {git_url}")
            results = self.client.sql_select(sql_query)
            if not results:
                return []

            matched_tasks = []
            for task in results:
                j_field = task.get('j', {})
                if isinstance(j_field, str):
                    try:
                        j_field = json.loads(j_field) if j_field else {}
                    except Exception:
                        j_field = {}

                introduced_errids = j_field.get('introduced_errids', [])
                if error_id in introduced_errids:
                    matched_tasks.append(task)
                    logger.info(
                        "Matched verified task | "
                        f"new_task: {new_task['id']} | "
                        f"verified_task: {task['id']} | "
                        f"first_bad_commit: {task.get('first_bad_commit', 'N/A')[:8]}"
                    )

            return matched_tasks

        except Exception as e:
            logger.error(f"Find matching verified tasks failed: {str(e)} | task_id: {new_task.get('id')}")
            logger.error(traceback.format_exc())
            return []

    def optimize_task(self, task: Dict, matched_verified_task: Dict) -> Dict:
        """Apply configured optimization strategy to one task."""
        try:
            task_id = task['id']
            verified_task_id = matched_verified_task['id']
            first_bad_commit = matched_verified_task.get('first_bad_commit')

            logger.info(
                "Optimize task | "
                f"task_id: {task_id} | "
                f"matched_task: {verified_task_id} | "
                f"strategy: {self.optimization_strategy}"
            )

            if self.optimization_strategy == 'reuse':
                return self._apply_reuse_strategy(task_id, verified_task_id, first_bad_commit)
            if self.optimization_strategy == 'verify':
                return self._apply_verify_strategy(task_id, verified_task_id, first_bad_commit)
            if self.optimization_strategy == 'priority':
                return self._apply_priority_strategy(task_id, verified_task_id)

            error_msg = f"unknown_optimization_strategy: {self.optimization_strategy}"
            logger.error(error_msg)
            return {'status': 'failed', 'error': error_msg}

        except Exception as e:
            error_msg = f"optimize_task_exception: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task.get('id')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg}

    def _apply_reuse_strategy(self, task_id: int, verified_task_id: int, first_bad_commit: str) -> Dict:
        """Strategy 1: directly reuse first_bad_commit and mark task success."""
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
                    "Task optimization success (reuse) | "
                    f"task_id: {task_id} | "
                    f"first_bad_commit: {first_bad_commit[:8]}"
                )
                return {'status': 'success', 'strategy': 'reuse', 'task_id': task_id}

            error_msg = "database_update_failed"
            logger.error(f"{error_msg} | task_id: {task_id}")
            return {'status': 'failed', 'error': error_msg}

        except Exception as e:
            error_msg = f"apply_reuse_strategy_failed: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task_id}")
            return {'status': 'failed', 'error': error_msg}

    def _apply_verify_strategy(self, task_id: int, verified_task_id: int, first_bad_commit: str) -> Dict:
        """Strategy 2: move task to pending_verification for fast boundary check."""
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
                    "Task optimization success (pending verification) | "
                    f"task_id: {task_id} | "
                    f"candidate: {first_bad_commit[:8]}"
                )
                return {'status': 'success', 'strategy': 'verify', 'task_id': task_id}

            error_msg = "database_update_failed"
            logger.error(f"{error_msg} | task_id: {task_id}")
            return {'status': 'failed', 'error': error_msg}

        except Exception as e:
            error_msg = f"apply_verify_strategy_failed: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task_id}")
            return {'status': 'failed', 'error': error_msg}

    def _apply_priority_strategy(self, task_id: int, verified_task_id: int) -> Dict:
        """Strategy 3: lower priority so other tasks run first."""
        try:
            current_time = int(time.time())
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
                logger.info(f"Task optimization success (priority) | task_id: {task_id}")
                return {'status': 'success', 'strategy': 'priority', 'task_id': task_id}

            error_msg = "database_update_failed"
            logger.error(f"{error_msg} | task_id: {task_id}")
            return {'status': 'failed', 'error': error_msg}

        except Exception as e:
            error_msg = f"apply_priority_strategy_failed: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task_id}")
            return {'status': 'failed', 'error': error_msg}

    def run_optimization_cycle(self) -> Dict[str, int]:
        """Run one optimization cycle and return summary stats."""
        try:
            logger.info("=" * 60)
            logger.info("Start optimization cycle")
            logger.info("=" * 60)

            pending_tasks = self.scan_pending_tasks()
            if not pending_tasks:
                logger.info("No pending tasks to optimize")
                return {'scanned': 0, 'optimized': 0, 'no_match': 0, 'failed': 0}

            stats = {'scanned': len(pending_tasks), 'optimized': 0, 'no_match': 0, 'failed': 0}

            for task in pending_tasks:
                try:
                    matched_tasks = self.find_matching_verified_tasks(task)
                    if not matched_tasks:
                        logger.debug(f"No verified match found | task_id: {task['id']}")
                        stats['no_match'] += 1
                        continue

                    result = self.optimize_task(task, matched_tasks[0])
                    if result.get('status') == 'success':
                        stats['optimized'] += 1
                    else:
                        stats['failed'] += 1

                except Exception as e:
                    logger.error(f"Optimize task exception: {str(e)} | task_id: {task.get('id')}")
                    stats['failed'] += 1

            logger.info("=" * 60)
            logger.info(
                "Optimization cycle completed | "
                f"scanned: {stats['scanned']} | "
                f"optimized: {stats['optimized']} | "
                f"no_match: {stats['no_match']} | "
                f"failed: {stats['failed']}"
            )
            logger.info("=" * 60)
            return stats

        except Exception as e:
            logger.error(f"Optimization cycle failed: {str(e)}")
            logger.error(traceback.format_exc())
            return {'scanned': 0, 'optimized': 0, 'no_match': 0, 'failed': 0, 'error': str(e)}


def create_task_optimizer(config: Dict) -> TaskOptimizer:
    """Create a TaskOptimizer instance from runtime config."""
    client = ManticoreClient(
        host=config.get('manticore_host', 'localhost'),
        port=int(config.get('manticore_http_port', '9308'))
    )
    return TaskOptimizer(client, config)


if __name__ == '__main__':
    config = {
        'manticore_host': os.environ.get('MANTICORE_HOST', 'localhost'),
        'manticore_http_port': os.environ.get('MANTICORE_HTTP_PORT', '9308'),
        'optimize_batch_size': 20,
        'optimize_interval': 1800,
        'optimization_strategy': 'verify'  # reuse / verify / priority
    }

    optimizer = create_task_optimizer(config)
    stats = optimizer.run_optimization_cycle()
    logger.info(f"Optimization cycle stats: {stats}")
