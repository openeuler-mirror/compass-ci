#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""


createbisecttask，。
"""

import time
from typing import List, Dict, Any, Tuple
from log_config import logger


class BatchInserter:
    """
    

    ：
    - createbisecttask
    - 
    - error
    - stats
    """

    def __init__(self, client, batch_size: int = 50):
        """
        initialize

        Args:
            client: ManticoreClientinstance
            batch_size: 
        """
        self.client = client
        self.batch_size = batch_size

        # stats
        self.stats = {
            'total_tasks': 0,
            'batches_processed': 0,
            'successful_inserts': 0,
            'failed_inserts': 0,
            'fallback_singles': 0,
            'total_time_ms': 0
        }

    def batch_create_tasks(self, tasks: List[Dict[str, Any]]) -> Tuple[int, int]:
        """
        createtask

        Args:
            tasks: tasklist，taskdict：
                - bad_job_id: errorjob ID
                - error_id: errorID
                - bisect_status: status（"wait"）
                - git_url: GitrepoURL
                - category: task
                - task

        Returns:
            (success, failed) 
        """
        if not tasks:
            return 0, 0

        start_time = time.time()
        success_count = 0
        failed_count = 0

        self.stats['total_tasks'] += len(tasks)

        logger.info(f"startcreatetask | : {len(tasks)} | : {self.batch_size}")

        # 
        for i in range(0, len(tasks), self.batch_size):
            batch = tasks[i:i + self.batch_size]
            batch_num = i // self.batch_size + 1
            total_batches = (len(tasks) + self.batch_size - 1) // self.batch_size

            logger.debug(f" {batch_num}/{total_batches} | task: {len(batch)}")

            try:
                # 
                batch_success = self._batch_insert(batch)
                success_count += batch_success
                failed_count += len(batch) - batch_success
                self.stats['batches_processed'] += 1

            except Exception as e:
                logger.warning(f"failed， | error: {str(e)}")
                # 
                single_success, single_failed = self._fallback_single_insert(batch)
                success_count += single_success
                failed_count += single_failed
                self.stats['fallback_singles'] += len(batch)

        # stats
        elapsed_ms = (time.time() - start_time) * 1000
        self.stats['successful_inserts'] += success_count
        self.stats['failed_inserts'] += failed_count
        self.stats['total_time_ms'] += elapsed_ms

        # 
        tasks_per_second = len(tasks) / (elapsed_ms / 1000) if elapsed_ms > 0 else 0

        logger.info(f"createcompleted | success: {success_count}/{len(tasks)} | "
                   f": {elapsed_ms:.2f}ms | : {tasks_per_second:.1f} tasks/s")

        return success_count, failed_count

    def _batch_insert(self, batch: List[Dict[str, Any]]) -> int:
        """
        （ ManticoreClient  batch_insert ）

        Args:
            batch: task

        Returns:
            successcount

        Raises:
            Exception: failedexception
        """
        #  ID 
        import sys
        import os
        sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lib'))
        from bisect_utils import _generate_task_id

        # dict
        documents = {}
        for task in batch:
            bad_job_id = task.get('bad_job_id', '')
            error_id = task.get('error_id', '')
            bisect_metric = task.get('bisect_metric', '')

            if not bad_job_id:
                logger.warning("task bad_job_id，skip")
                continue

            #  task_identifier（ task_processor.py ）
            if error_id:
                task_identifier = f"error_id='{error_id}'"
            elif bisect_metric:
                task_identifier = f"bisect_metric='{bisect_metric}'"
            else:
                logger.warning("task error_id  bisect_metric，skip")
                continue

            # 🔧  ID 
            task_id = _generate_task_id(bad_job_id, task_identifier)

            # （ id ）
            doc = {k: v for k, v in task.items() if k != 'id'}
            documents[task_id] = doc

        if not documents:
            logger.warning("task")
            return 0

        try:
            #  ManticoreClient  batch_insert 
            logger.debug(f" | : {len(documents)}")
            result = self.client.batch_insert("bisect", documents)

            if result:
                logger.debug(f"success |  {len(documents)} ")
                return len(documents)
            else:
                logger.warning("failed")
                # failed，exception
                raise Exception("failed")

        except AttributeError as e:
            # ManticoreClient  batch_insert ，
            logger.warning(f"ManticoreClient support batch_insert: {e}")
            raise Exception("support") from e

        except Exception as e:
            logger.error(f"exception: {str(e)}")
            raise

    def _fallback_single_insert(self, batch: List[Dict[str, Any]]) -> Tuple[int, int]:
        """
        （failed）

        Args:
            batch: task

        Returns:
            (success, failed) 
        """
        #  ID 
        import sys
        import os
        sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lib'))
        from bisect_utils import _generate_task_id

        success_count = 0
        failed_count = 0

        for task in batch:
            try:
                bad_job_id = task.get('bad_job_id', '')
                error_id = task.get('error_id', '')
                bisect_metric = task.get('bisect_metric', '')

                if not bad_job_id:
                    logger.warning("task bad_job_id，skip")
                    failed_count += 1
                    continue

                #  task_identifier（ task_processor.py ）
                if error_id:
                    task_identifier = f"error_id='{error_id}'"
                elif bisect_metric:
                    task_identifier = f"bisect_metric='{bisect_metric}'"
                else:
                    logger.warning("task error_id  bisect_metric，skip")
                    failed_count += 1
                    continue

                # 🔧  ID 
                task_id = _generate_task_id(bad_job_id, task_identifier)

                # （ id ）
                doc = {k: v for k, v in task.items() if k != 'id'}

                result = self.client.replace("bisect", task_id, doc)

                if result:
                    success_count += 1
                else:
                    # replace failed, try insert as last resort
                    insert_result = self.client.insert("bisect", task_id, doc)
                    if insert_result:
                        success_count += 1
                    else:
                        failed_count += 1

            except Exception as e:
                logger.debug(f"Single insert failed | error_id: {task.get('error_id', 'unknown')[:50]}... | error: {str(e)}")
                failed_count += 1

        return success_count, failed_count

    def get_stats(self) -> Dict[str, Any]:
        """
        getstats

        Returns:
            statsdict
        """
        avg_time_per_task = self.stats['total_time_ms'] / self.stats['total_tasks'] \
            if self.stats['total_tasks'] > 0 else 0

        success_rate = self.stats['successful_inserts'] / self.stats['total_tasks'] \
            if self.stats['total_tasks'] > 0 else 0

        return {
            **self.stats,
            'avg_time_per_task_ms': avg_time_per_task,
            'success_rate': success_rate,
            'batch_size': self.batch_size
        }

    def reset_stats(self):
        """resetstats"""
        self.stats = {
            'total_tasks': 0,
            'batches_processed': 0,
            'successful_inserts': 0,
            'failed_inserts': 0,
            'fallback_singles': 0,
            'total_time_ms': 0
        }