#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
任务标记模块 (Task Marking Module)

职责：处理任务状态标记的业务逻辑
- 查找相似任务
- 批量标记任务状态
- 验证任务关联关系

按照 code-spec.md 规范：
- 每个函数不超过 10 行
- 业务层和底层逻辑分离
- 日志字符串 grep-friendly
"""

import time
import traceback
from typing import Dict, List, Optional
from log_config import logger


class TaskMarker:
    """
    任务标记器

    grep 关键字: "task marker"
    """

    def __init__(self, client, errid_intelligence):
        """初始化任务标记器"""
        self.client = client
        self.errid_intelligence = errid_intelligence

    # ========================================
    # 业务层：协调逻辑
    # ========================================

    def mark_similar_wait_tasks(self, successful_task: Dict) -> Dict[str, int]:
        """
        业务层：标记相似的 wait 任务为 verifying

        返回: {'success': N, 'failed': N}
        grep: "mark similar wait tasks"
        """
        if not self._should_process(successful_task):
            return {'success': 0, 'failed': 0}

        signature = self._extract_signature(successful_task)

        # Only reuse when signature has a real file path (e.g., "nbl_core/nbl_service.c::error")
        # Config-stage signatures without file paths (makepkg::, stderr::, unknown_file::)
        # are too coarse and cause false matches
        file_key = signature.split('::')[0]
        if '/' not in file_key and '.' not in file_key:
            logger.info(f"mark similar wait tasks | skip no-file signature | task_id: {successful_task.get('id')} | signature: {signature}")
            return {'success': 0, 'failed': 0}

        success_git_url = successful_task.get('git_url', '')
        similar_tasks = self._find_similar_tasks(signature, success_git_url)
        result = self._batch_mark_verifying(similar_tasks, successful_task['id'], signature)

        logger.info(f"mark similar wait tasks | completed | task_id: {successful_task['id']} | "
                   f"signature: {signature} | success: {result['success']} | failed: {result['failed']}")
        return result

    def _should_process(self, task: Dict) -> bool:
        """业务层：判断任务是否需要处理"""
        category = task.get('category', 'function')
        error_id = task.get('error_id', '')
        should_process = (category == 'build' and bool(error_id))

        if not should_process:
            logger.debug(f"mark similar wait tasks | skip | task_id: {task.get('id')} | "
                        f"category: {category} | has_error_id: {bool(error_id)}")
        return should_process

    def _extract_signature(self, task: Dict) -> str:
        """业务层：提取任务错误签名"""
        error_id = task.get('error_id', '')
        signature = self.errid_intelligence.extract_coarse_signature(error_id)
        logger.debug(f"mark similar wait tasks | extract signature | task_id: {task['id']} | signature: {signature}")
        return signature

    def _find_similar_tasks(self, signature: str, git_url: str = '') -> List[Dict]:
        """业务层：查找相似任务（协调底层查询和过滤）"""
        wait_tasks = self._query_wait_build_tasks()
        similar_tasks = self._filter_by_signature(wait_tasks, signature, git_url)

        logger.info(f"mark similar wait tasks | find similar | signature: {signature} | "
                   f"total_wait: {len(wait_tasks)} | similar: {len(similar_tasks)}")
        return similar_tasks

    # ========================================
    # 底层：数据访问
    # ========================================

    def _query_wait_build_tasks(self, limit: int = 1000) -> List[Dict]:
        """底层：查询 wait 状态的构建任务"""
        query = """
            SELECT id, error_id, bad_job_id, git_url, submit_time, priority_level
            FROM bisect
            WHERE bisect_status = 'wait' AND category = 'build'
            LIMIT %s
        """
        try:
            tasks = self.client.sql_select(query, (limit,))
            logger.debug(f"query wait build tasks | found: {len(tasks) if tasks else 0}")
            return tasks or []
        except Exception as e:
            logger.error(f"query wait build tasks | failed | error: {str(e)}")
            return []

    def _filter_by_signature(self, tasks: List[Dict], target_signature: str, git_url: str = '') -> List[Dict]:
        """底层：按签名和 git_url 过滤任务"""
        similar = []
        skipped_cross_repo = 0
        for task in tasks:
            error_id = task.get('error_id', '')
            if not error_id:
                continue

            try:
                signature = self.errid_intelligence.extract_coarse_signature(error_id)
                if signature == target_signature:
                    if git_url and task.get('git_url', '') != git_url:
                        skipped_cross_repo += 1
                        continue
                    similar.append(task)
            except Exception as e:
                logger.warning(f"filter by signature | extract failed | task_id: {task.get('id')} | error: {str(e)}")
                continue

        if skipped_cross_repo:
            logger.info(f"filter by signature | skipped cross-repo: {skipped_cross_repo}")
        return similar

    def _batch_mark_verifying(self, tasks: List[Dict], related_id: str, signature: str) -> Dict[str, int]:
        """底层：批量标记任务为 verifying"""
        if not tasks:
            return {'success': 0, 'failed': 0}

        current_time = int(time.time())
        success_count = 0
        failed_count = 0

        for task in tasks:
            if self._mark_single_verifying(task['id'], related_id, signature, task.get('error_id', ''), current_time):
                success_count += 1
            else:
                failed_count += 1

        return {'success': success_count, 'failed': failed_count}

    def _mark_single_verifying(self, task_id: str, related_id: str, signature: str,
                                error_id: str, timestamp: int) -> bool:
        """底层：标记单个任务为 verifying"""
        doc = {
            "bisect_status": "verifying",
            "updated_at": timestamp,
            "j": {
                "related_task_id": str(related_id),
                "error_signature": signature,
                "original_error_id": error_id,
                "auto_marked_by_success": True,
                "auto_marked_timestamp": timestamp
            }
        }

        try:
            result = self.client.update("bisect", task_id, doc)
            if result:
                logger.debug(f"mark single verifying | success | task_id: {task_id} | related: {related_id}")
            else:
                logger.warning(f"mark single verifying | failed | task_id: {task_id}")
            return bool(result)
        except Exception as e:
            logger.error(f"mark single verifying | error | task_id: {task_id} | error: {str(e)}")
            return False


# ========================================
# 便捷函数（用于向后兼容）
# ========================================

def mark_similar_wait_tasks_for_verification(client, errid_intelligence, successful_task: Dict) -> Dict[str, int]:
    """
    便捷函数：标记相似的 wait 任务

    用于替换 TaskProcessor._mark_similar_wait_tasks_for_verification
    向后兼容旧代码
    """
    marker = TaskMarker(client, errid_intelligence)
    return marker.mark_similar_wait_tasks(successful_task)
