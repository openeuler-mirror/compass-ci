#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
批量插入工具

用于批量创建bisect任务，减少数据库交互次数。
"""

import time
from typing import List, Dict, Any, Tuple
from log_config import logger


class BatchInserter:
    """
    批量插入管理器

    特性：
    - 批量创建bisect任务
    - 自动处理批次大小
    - 错误时回退到单个插入
    - 统计插入性能
    """

    def __init__(self, client, batch_size: int = 50):
        """
        初始化批量插入器

        Args:
            client: ManticoreClient实例
            batch_size: 每批次的大小
        """
        self.client = client
        self.batch_size = batch_size

        # 统计信息
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
        批量创建任务

        Args:
            tasks: 任务列表，每个任务是一个字典包含：
                - bad_job_id: 错误job ID
                - error_id: 错误ID
                - bisect_status: 状态（通常是"wait"）
                - git_url: Git仓库URL
                - category: 任务分类
                - 其他任务字段

        Returns:
            (成功数, 失败数) 元组
        """
        if not tasks:
            return 0, 0

        start_time = time.time()
        success_count = 0
        failed_count = 0

        self.stats['total_tasks'] += len(tasks)

        logger.info(f"开始批量创建任务 | 总数: {len(tasks)} | 批次大小: {self.batch_size}")

        # 按批次处理
        for i in range(0, len(tasks), self.batch_size):
            batch = tasks[i:i + self.batch_size]
            batch_num = i // self.batch_size + 1
            total_batches = (len(tasks) + self.batch_size - 1) // self.batch_size

            logger.debug(f"处理批次 {batch_num}/{total_batches} | 任务数: {len(batch)}")

            try:
                # 尝试批量插入
                batch_success = self._batch_insert(batch)
                success_count += batch_success
                failed_count += len(batch) - batch_success
                self.stats['batches_processed'] += 1

            except Exception as e:
                logger.warning(f"批量插入失败，回退到单个插入 | 错误: {str(e)}")
                # 回退到单个插入
                single_success, single_failed = self._fallback_single_insert(batch)
                success_count += single_success
                failed_count += single_failed
                self.stats['fallback_singles'] += len(batch)

        # 更新统计
        elapsed_ms = (time.time() - start_time) * 1000
        self.stats['successful_inserts'] += success_count
        self.stats['failed_inserts'] += failed_count
        self.stats['total_time_ms'] += elapsed_ms

        # 计算性能指标
        tasks_per_second = len(tasks) / (elapsed_ms / 1000) if elapsed_ms > 0 else 0

        logger.info(f"批量创建完成 | 成功: {success_count}/{len(tasks)} | "
                   f"耗时: {elapsed_ms:.2f}ms | 速率: {tasks_per_second:.1f} tasks/s")

        return success_count, failed_count

    def _batch_insert(self, batch: List[Dict[str, Any]]) -> int:
        """
        执行真正的批量插入（使用 ManticoreClient 的 batch_insert 方法）

        Args:
            batch: 任务批次

        Returns:
            成功插入的数量

        Raises:
            Exception: 当整个批次插入失败时抛出异常
        """
        # 导入正确的 ID 生成函数
        import sys
        import os
        sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lib'))
        from bisect_utils import _generate_task_id

        # 构建批量插入的数据字典
        documents = {}
        for task in batch:
            bad_job_id = task.get('bad_job_id', '')
            error_id = task.get('error_id', '')
            bisect_metric = task.get('bisect_metric', '')

            if not bad_job_id:
                logger.warning("任务缺少 bad_job_id，跳过")
                continue

            # 构建 task_identifier（与 task_processor.py 保持一致）
            if error_id:
                task_identifier = f"error_id='{error_id}'"
            elif bisect_metric:
                task_identifier = f"bisect_metric='{bisect_metric}'"
            else:
                logger.warning("任务既没有 error_id 也没有 bisect_metric，跳过")
                continue

            # 🔧 使用正确的 ID 生成方式
            task_id = _generate_task_id(bad_job_id, task_identifier)

            # 准备文档内容（不包含 id 字段）
            doc = {k: v for k, v in task.items() if k != 'id'}
            documents[task_id] = doc

        if not documents:
            logger.warning("批次中没有有效的任务")
            return 0

        try:
            # 使用 ManticoreClient 的 batch_insert 方法进行真正的批量插入
            logger.debug(f"执行真正的批量插入 | 文档数: {len(documents)}")
            result = self.client.batch_insert("bisect", documents)

            if result:
                logger.debug(f"批量插入成功 | 插入 {len(documents)} 个文档")
                return len(documents)
            else:
                logger.warning("批量插入返回失败")
                # 如果批量插入失败，抛出异常触发回退
                raise Exception("批量插入操作失败")

        except AttributeError as e:
            # ManticoreClient 没有 batch_insert 方法，回退到逐个插入
            logger.warning(f"ManticoreClient 不支持 batch_insert: {e}")
            raise Exception("不支持批量插入") from e

        except Exception as e:
            logger.error(f"批量插入异常: {str(e)}")
            raise

    def _fallback_single_insert(self, batch: List[Dict[str, Any]]) -> Tuple[int, int]:
        """
        回退到单个插入（当批量插入失败时）

        Args:
            batch: 任务批次

        Returns:
            (成功数, 失败数) 元组
        """
        # 导入正确的 ID 生成函数
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
                    logger.warning("任务缺少 bad_job_id，跳过")
                    failed_count += 1
                    continue

                # 构建 task_identifier（与 task_processor.py 保持一致）
                if error_id:
                    task_identifier = f"error_id='{error_id}'"
                elif bisect_metric:
                    task_identifier = f"bisect_metric='{bisect_metric}'"
                else:
                    logger.warning("任务既没有 error_id 也没有 bisect_metric，跳过")
                    failed_count += 1
                    continue

                # 🔧 使用正确的 ID 生成方式
                task_id = _generate_task_id(bad_job_id, task_identifier)

                # 准备文档内容（不包含 id 字段）
                doc = {k: v for k, v in task.items() if k != 'id'}

                result = self.client.insert("bisect", task_id, doc)

                if result:
                    success_count += 1
                else:
                    failed_count += 1

            except Exception as e:
                logger.debug(f"单个插入失败 | error_id: {task.get('error_id', 'unknown')[:50]}... | 错误: {str(e)}")
                failed_count += 1

        return success_count, failed_count

    def get_stats(self) -> Dict[str, Any]:
        """
        获取批量插入统计信息

        Returns:
            统计信息字典
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
        """重置统计信息"""
        self.stats = {
            'total_tasks': 0,
            'batches_processed': 0,
            'successful_inserts': 0,
            'failed_inserts': 0,
            'fallback_singles': 0,
            'total_time_ms': 0
        }