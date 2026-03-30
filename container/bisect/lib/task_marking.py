#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Task Marking Module

Responsibilities: handle business logic for task status marking
- Find similar tasks
- Batch mark task status
- Validate task associations

Following code-spec.md conventions:
- Each function no more than 10 lines
- Business layer and data layer separation
- Log strings are grep-friendly
"""

import time
import traceback
from typing import Dict, List, Optional
from log_config import logger


class TaskMarker:
    """
    Task Marker

    grep keyword: "task marker"
    """

    def __init__(self, client, errid_intelligence):
        """Initialize task marker"""
        self.client = client
        self.errid_intelligence = errid_intelligence

    # ========================================
    # Business layer: coordination logic
    # ========================================

    def mark_similar_wait_tasks(self, successful_task: Dict) -> Dict[str, int]:
        """
        Business layer: mark similar wait tasks as verifying

        Returns: {'success': N, 'failed': N}
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
        result = self._batch_mark_pending_verification(similar_tasks, successful_task['id'], signature)

        logger.info(f"mark similar wait tasks | completed | task_id: {successful_task['id']} | "
                   f"signature: {signature} | success: {result['success']} | failed: {result['failed']}")
        return result

    def _should_process(self, task: Dict) -> bool:
        """Business layer: determine if task needs processing"""
        category = task.get('category', 'function')
        error_id = task.get('error_id', '')
        should_process = (category == 'build' and bool(error_id))

        if not should_process:
            logger.debug(f"mark similar wait tasks | skip | task_id: {task.get('id')} | "
                        f"category: {category} | has_error_id: {bool(error_id)}")
        return should_process

    def _extract_signature(self, task: Dict) -> str:
        """Business layer: extract task error signature"""
        error_id = task.get('error_id', '')
        signature = self.errid_intelligence.extract_coarse_signature(error_id)
        logger.debug(f"mark similar wait tasks | extract signature | task_id: {task['id']} | signature: {signature}")
        return signature

    def _find_similar_tasks(self, signature: str, git_url: str = '') -> List[Dict]:
        """Business layer: find similar tasks (coordinate query and filter)"""
        wait_tasks = self._query_wait_build_tasks()
        similar_tasks = self._filter_by_signature(wait_tasks, signature, git_url)

        logger.info(f"mark similar wait tasks | find similar | signature: {signature} | "
                   f"total_wait: {len(wait_tasks)} | similar: {len(similar_tasks)}")
        return similar_tasks

    # ========================================
    # Data layer: data access
    # ========================================

    def _query_wait_build_tasks(self, limit: int = 1000) -> List[Dict]:
        """Data layer: query build tasks in wait status"""
        query = f"""
            SELECT id, error_id, bad_job_id, git_url, submit_time, priority_level
            FROM bisect
            WHERE bisect_status = 'wait' AND category = 'build'
            LIMIT {limit}
            OPTION max_matches={limit}
        """
        try:
            tasks = self.client.sql_select(query)
            logger.debug(f"query wait build tasks | found: {len(tasks) if tasks else 0}")
            return tasks or []
        except Exception as e:
            logger.error(f"query wait build tasks | failed | error: {str(e)}")
            return []

    def _filter_by_signature(self, tasks: List[Dict], target_signature: str, git_url: str = '') -> List[Dict]:
        """Data layer: filter tasks by signature and git_url"""
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

    def _batch_mark_pending_verification(self, tasks: List[Dict], related_id: str, signature: str) -> Dict[str, int]:
        """Data layer: batch mark tasks as pending verification"""
        if not tasks:
            return {'success': 0, 'failed': 0}

        current_time = int(time.time())
        success_count = 0
        failed_count = 0

        for task in tasks:
            if self._mark_single_pending_verification(
                task['id'], related_id, signature, task.get('error_id', ''), current_time
            ):
                success_count += 1
            else:
                failed_count += 1

        return {'success': success_count, 'failed': failed_count}

    def _mark_single_pending_verification(self, task_id: str, related_id: str, signature: str,
                                           error_id: str, timestamp: int) -> bool:
        """Data layer: mark a single task as pending verification"""
        doc = {
            "bisect_status": "pending_verification",
            "updated_at": timestamp,
            "j": {
                "related_task_id": str(related_id),
                "error_signature": signature,
                "original_error_id": error_id,
                "auto_marked_by_success": True,
                "auto_marked_timestamp": timestamp,
                "verification_status": "pending"
            }
        }

        try:
            result = self.client.update("bisect", task_id, doc)
            if result:
                logger.debug(
                    f"mark single pending_verification | success | task_id: {task_id} | related: {related_id}"
                )
            else:
                logger.warning(f"mark single pending_verification | failed | task_id: {task_id}")
            return bool(result)
        except Exception as e:
            logger.error(f"mark single pending_verification | error | task_id: {task_id} | error: {str(e)}")
            return False


# ========================================
# Convenience functions (backward compatibility)
# ========================================

def mark_similar_wait_tasks_for_verification(client, errid_intelligence, successful_task: Dict) -> Dict[str, int]:
    """
    Convenience function: mark similar wait tasks

    Replaces TaskProcessor._mark_similar_wait_tasks_for_verification
    Backward compatible with old code
    """
    marker = TaskMarker(client, errid_intelligence)
    return marker.mark_similar_wait_tasks(successful_task)
