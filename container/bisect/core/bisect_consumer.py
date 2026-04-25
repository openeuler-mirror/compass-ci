#!/usr/bin/env python3

"""Bisect consumer that executes queued bisect tasks and persists results."""



import sys
import os
import re
import time
import hashlib
import shutil
import traceback
import json

from datetime import datetime
from typing import Dict, Any, Optional, List

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger, StructuredLogger
from bisect_utils import extract_repo_name_from_url
from notification_writer import NotificationWriter

sys.path.append((os.environ['LKP_SRC']) + '/sbin/bisect/')
from lkp_bisect.db.manticore import ManticoreClient
from lkp_bisect.core.git_bisect import GitBisect

class BisectConsumer:
    """Bisect task consumer"""

    _INVALID_COMMIT_TOKENS = {'n/a', 'na', 'none', 'null', 'unknown', '-'}

    def __init__(self, client: ManticoreClient, config: Dict):
        self.client = client
        self.config = config
        self.notification_writer = NotificationWriter(
            notification_dir=config.get('notification_dir', '/result/bisect/notifications')
        )
        self.task_deleted_checker = config.get('task_deleted_checker')
        logger.debug("BisectConsumer initialized with NotificationWriter")

    def _is_task_deleted(self, task_id: Optional[int]) -> bool:
        """Return True when the task was deleted after entering runtime state."""
        checker = getattr(self, 'task_deleted_checker', None)
        if task_id is None or checker is None:
            return False
        try:
            return bool(checker(task_id))
        except Exception as e:
            logger.warning(f"task_deleted_checker failed | task_id: {task_id} | error: {e}")
            return False

    @staticmethod
    def _raw_sql_affected_rows(raw_result: Any) -> int:
        """Extract affected-row count from Manticore raw SQL responses."""
        if not raw_result or not isinstance(raw_result, list):
            return 0

        first = raw_result[0]
        if not isinstance(first, dict) or first.get('error'):
            return 0

        for key in ('total', 'affected_rows', 'affected', 'updated', 'rowcount'):
            value = first.get(key)
            if value is None:
                continue
            try:
                return int(value)
            except (TypeError, ValueError):
                continue
        return 0

    def _deleted_task_result(self, task_id: int, phase: str) -> Dict:
        """Return a consistent skip result when delete_tasks removed a live task."""
        logger.info(f"Task deleted during processing, skipping {phase} | task_id: {task_id}")
        return {'status': 'skipped', 'id': task_id, 'error': f'Task deleted during {phase}'}

    def process_single_task(self, task: Dict) -> Dict:
        """Process a single bisect task"""
        try:
            task_id = int(task['id'])
            if self._is_task_deleted(task_id):
                return self._deleted_task_result(task_id, 'startup')

            # Prefer the result root that was allocated at submit time. Fall back to
            # generating it here for tasks created before the submit-time allocator.
            task_result_root = task.get('bisect_result_root') or self._generate_task_path(self.config, task)

            # Debug log for result_root
            logger.debug(f"Generated task_result_root: {task_result_root} | task_id: {task_id}")

            if not task_result_root:
                logger.error(f"Failed to generate task_result_root | task_id: {task_id}")
                return {'status': 'failed', 'error': 'Failed to generate result_root', 'id': task_id, 'bad_job_id': task.get('bad_job_id', 'N/A')}

            # Use atomic operation to update task status, avoid race conditions
            current_time = int(time.time())
            update_query = f"""
                UPDATE bisect
                SET bisect_status = 'processing', updated_at = {current_time}, start_time = {current_time}
                WHERE id = {task_id} AND bisect_status = 'wait'
            """

            # Execute atomic update
            update_result = self.client.sql_raw(update_query)
            affected_rows = self._raw_sql_affected_rows(update_result)

            # Check if update succeeded (returns affected rows)
            if affected_rows <= 0:
                logger.warning(f"Skipping task | ID: {task_id} | status changed, deleted, or not exists")
                return {'status': 'skipped', 'id': task_id, 'error': 'Task status changed, deleted, or not exists'}

            if self._is_task_deleted(task_id):
                return self._deleted_task_result(task_id, 'claim')

            logger.info(f"Start processing task | ID: {task_id}")

            # Note: similar task clustering and marking is done in task_processor._cluster_and_select_tasks
            # No longer operating on other tasks in single task processing to avoid concurrency issues and duplicate logic

            # Prepare task data
            logger.debug(f"Step 1: Preparing task data | ID: {task_id}")
            task['bisect_result_root'] = task_result_root

            # Get shared repository
            logger.debug(f"Step 2: Getting git_url | ID: {task_id}")
            repo_url = task.get("git_url")
            if not repo_url:
                logger.error("Task missing repository URL")
                return {'status': 'failed', 'error': 'Missing git_url', 'id': task_id, 'bad_job_id': task.get('bad_job_id', 'N/A')}

            logger.debug(f"Step 3: Extracting good_commit from j field | ID: {task_id}")
            # Extract good_commit from j field BEFORE validation
            # This ensures validated_data contains good_commit from the start
            # Compatible with two field naming conventions:
            #   - New tasks use good_commit/bad_commit
            #   - Recovered tasks may only have start_commit/end_commit (overwritten after bisect execution)
            j_field = task.get('j') or {}
            logger.info(f"j_field raw value | task_id: {task_id} | type: {type(j_field).__name__} | value: {str(j_field)[:200]}")
            if isinstance(j_field, str):
                try:
                    j_field = json.loads(j_field) if j_field else {}
                    logger.info(f"j_field parsed from string | task_id: {task_id}")
                except json.JSONDecodeError:
                    j_field = {}
                    logger.warning(f"j_field parse failed | task_id: {task_id}")
            elif not isinstance(j_field, dict):
                logger.warning(f"j_field is not dict | task_id: {task_id} | type: {type(j_field).__name__}")
                j_field = {}

            # Prefer good_commit, fallback to start_commit (compatible with recovery scenario)
            good_commit = j_field.get('good_commit') or j_field.get('start_commit')
            if good_commit:
                task['good_commit'] = good_commit
                source = 'good_commit' if j_field.get('good_commit') else 'start_commit'
                logger.info(f"Extracted good_commit from j.{source} | task_id: {task_id} | good_commit: {good_commit}")
            else:
                logger.warning(f"No good_commit/start_commit in j field | task_id: {task_id} | j_field keys: {list(j_field.keys()) if isinstance(j_field, dict) else 'N/A'}")

            # Also compatible with bad_commit and end_commit
            bad_commit = j_field.get('bad_commit') or j_field.get('end_commit')
            if bad_commit:
                task['bad_commit'] = bad_commit
                source = 'bad_commit' if j_field.get('bad_commit') else 'end_commit'
                logger.debug(f"Extracted bad_commit from j.{source} | task_id: {task_id} | bad_commit: {bad_commit}")

            # Extract midpoint range info computed by producer (for performance bisect)
            v1_range = j_field.get('v1_range')
            v2_range = j_field.get('v2_range')
            mid_point = j_field.get('mid_point')
            if v1_range is not None and v2_range is not None:
                task['v1_range'] = v1_range
                task['v2_range'] = v2_range
                if mid_point is not None:
                    task['mid_point'] = mid_point
                logger.debug(f"Extracted range from j | task_id: {task_id} | v1_range: {v1_range} | v2_range: {v2_range} | mid_point: {mid_point}")

            logger.debug(f"Step 4: Validating task data | ID: {task_id}")
            # Validate task data
            validated_data = self._validate_task_data(task)
            if 'error' in validated_data:
                return validated_data

            logger.debug(f"Step 5: Checking task type | ID: {task_id}")
            # Check task type
            task_type_result = self._check_task_type(task)
            if 'error' in task_type_result:
                return task_type_result

            # Execute bisect with context manager to ensure repo release
            # Use context manager to ensure repo is always released, even on exception or crash
            with self.repo_manager.get_repo_context(
                task['id'],
                task['bad_job_id'],
                repo_url
            ) as (repo_dir, job_dir):
                logger.info(f"Using shared repository | path: {repo_dir}")

                # Execute GitBisect
                gb = GitBisect()
                result = gb.find_first_bad_commit(validated_data, repo_dir=repo_dir)

                # Handle results based on task type (no manual repo release needed)
                task_type = task_type_result.get('task_type', 'error')
                if task_type == 'performance':
                    return self._handle_performance_bisect_result(result, task, task_id)
                else:
                    return self._handle_bisect_result_no_release(result, task, task_id)

        except Exception as e:
            error_msg = f"Task {task.get('id', 'unknown_id')} failed: {str(e)}"
            logger.error(error_msg)

            # Update database status to failed
            task_id = task.get('id')
            if task_id:
                if self._is_task_deleted(task_id):
                    return self._deleted_task_result(int(task_id), 'exception handling')
                try:
                    # Generate bisect_result_root, set even in exception cases
                    bisect_result_root = task.get('bisect_result_root')
                    if not bisect_result_root:
                        try:
                            bisect_result_root = self._generate_task_path(self.config, task)
                            logger.info(f"Generated bisect_result_root for failed task: {bisect_result_root}")
                        except Exception as path_e:
                            logger.error(f"Failed to generate path for failed task: {str(path_e)}")
                            bisect_result_root = ""

                    fail_doc = {
                        "bisect_status": "failed",
                        "last_error": error_msg,
                        "bisect_result_root": bisect_result_root,
                        "updated_at": int(time.time())
                    }
                    self.client.update("bisect", task_id, fail_doc)
                    logger.info(f"Updated failed task status to failed | ID: {task_id}")
                except Exception as update_e:
                    logger.error(f"Failed to update failed task status: {str(update_e)}")

            return {'id': task.get('id', 'unknown_id'), 'status': 'failed', 'error': error_msg, 'bad_job_id': task.get('bad_job_id', 'N/A')}

    def _calculate_confidence_from_git_verification(
        self, git_verification: Dict, boundary_verification: Dict, task_id: int
    ) -> str:
        """
        Calculate confidence based on git verification results

        Args:
            git_verification: git verification result (contains verified, confidence (0.0/0.5/1.0), file_analysis, etc.)
            boundary_verification: boundary verification info
            task_id: task ID

        Returns:
            'high', 'medium', 'low'
        """
        try:
            # Strategy 1: if git_verification.confidence exists, map directly
            if git_verification and 'confidence' in git_verification:
                confidence_score = git_verification.get('confidence', 0.0)
                need_human_judgment = git_verification.get('need_human_judgment', False)
                verified = git_verification.get('verified', False)

                # Direct mapping: 1.0 -> high, 0.5 -> medium, 0.0 -> low
                if confidence_score >= 1.0:
                    confidence = 'high'
                elif confidence_score >= 0.5:
                    confidence = 'medium'
                else:
                    confidence = 'low'

                logger.info(
                    f"Using git_verification confidence | task_id: {task_id} | "
                    f"score: {confidence_score} | level: {confidence} | "
                    f"verified: {verified} | need_human_judgment: {need_human_judgment}"
                )
                return confidence

            # Strategy 2: check if boundary verification passed
            verification_passed = boundary_verification.get('verification_passed', False)
            if verification_passed:
                logger.info(
                    f"Boundary verification passed, no git verification | task_id: {task_id} | "
                    f"confidence: medium (fallback)"
                )
                return 'medium'

            # Strategy 3: default low
            logger.warning(
                f"No verification data | task_id: {task_id} | confidence: low (default)"
            )
            return 'low'

        except Exception as e:
            logger.error(f"Failed to calculate confidence | task_id: {task_id} | error: {str(e)}")
            return 'low'

    # Note: _find_and_mark_similar_tasks and _promote_pending_verification_tasks have been removed
    # Similar task clustering and marking is now handled in task_processor._cluster_and_select_tasks
    # Avoids concurrency issues and duplicate logic from operating on other tasks in single task processing

    def _validate_task_data(self, task: Dict) -> Dict:
        """Validate task data"""
        validated = task.copy()

        # Ensure j field is not null
        if 'j' in validated and validated['j'] is None:
            logger.warning(f"Cleaning invalid j field | task_id={validated.get('id')}")
            validated['j'] = {}

        # Ensure basic required fields exist
        if 'bad_job_id' not in validated:
            return {'error': 'Missing bad_job_id', 'id': validated.get('id', 'unknown_id')}

        if not validated['bad_job_id'] or not str(validated['bad_job_id']).strip():
            return {'error': 'Invalid bad_job_id', 'id': validated.get('id', 'unknown_id')}

        # Check task type: must have either error_id or bisect_metric
        has_error_id = validated.get("error_id") and str(validated["error_id"]).strip()
        has_metrics = validated.get("bisect_metric") is not None and str(validated["bisect_metric"]).strip() != ""

        # Truncate long strings for logging to avoid spam
        log_error_id = (validated.get('error_id', 'None')[:100] + '...') if len(validated.get('error_id', '')) > 100 else validated.get('error_id', 'None')
        log_bisect_metric = (str(validated.get('bisect_metric', 'None'))[:100] + '...') if len(str(validated.get('bisect_metric', ''))) > 100 else validated.get('bisect_metric', 'None')

        logger.debug(f"Task type check | Task ID: {validated.get('id')} | error_id: '{log_error_id}' | bisect_metric: '{log_bisect_metric}' | has_error_id: {has_error_id} | has_metrics: {has_metrics}")

        if not has_error_id and not has_metrics:
            return {'error': 'Missing task type: must specify either error_id or bisect_metric', 'id': validated.get('id', 'unknown_id')}

        if has_error_id and has_metrics:
            return {'error': 'Task type conflict: cannot specify both error_id and bisect_metric', 'id': validated.get('id', 'unknown_id')}

        # Clean empty string fields
        cleaned_data = {}
        for key, value in validated.items():
            if isinstance(value, str) and value.strip() == '':
                continue  # Skip empty string fields
            cleaned_data[key] = value

        # Reject placeholder commit refs early (e.g., "N/A"), which cannot be bisected.
        # But allow missing good/start commit and let downstream logic derive it.
        good_commit = cleaned_data.get('good_commit') or cleaned_data.get('start_commit')
        good_commit_present = ('good_commit' in cleaned_data) or ('start_commit' in cleaned_data)
        if good_commit_present and self._is_invalid_commit_ref(good_commit):
            return {
                'error': f'Invalid good commit reference: {good_commit}',
                'id': cleaned_data.get('id', 'unknown_id')
            }

        bad_commit = cleaned_data.get('bad_commit') or cleaned_data.get('end_commit')
        if bad_commit is not None and self._is_invalid_commit_ref(bad_commit):
            return {
                'error': f'Invalid bad commit reference: {bad_commit}',
                'id': cleaned_data.get('id', 'unknown_id')
            }

        return cleaned_data

    @classmethod
    def _is_invalid_commit_ref(cls, value: Any) -> bool:
        """Return True for placeholder/non-actionable commit refs."""
        if value is None:
            return True
        ref = str(value).strip()
        if not ref:
            return True
        return ref.lower() in cls._INVALID_COMMIT_TOKENS

    def _check_task_type(self, task: Dict) -> Dict:
        """Check task type"""
        has_error_id = task.get("error_id") and str(task["error_id"]).strip()
        has_metrics = task.get("bisect_metric") is not None and str(task["bisect_metric"]).strip() != ""

        if not has_error_id and not has_metrics:
            return {'error': 'Missing task type: must specify either error_id or bisect_metric'}

        if has_error_id and has_metrics:
            return {'error': 'Task type conflict: cannot specify both error_id and bisect_metric'}

        return {'task_type': 'error' if has_error_id else 'performance'}

    def _get_repo_dir(self, task_id: str, bad_job_id: str, repo_url: str):
        """Get repository directory"""
        # Need to inject repo_manager from external
        if not hasattr(self, 'repo_manager'):
            sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
            from repo_manager import SharedRepoManager
            self.repo_manager = SharedRepoManager()

        return self.repo_manager.get_repo_dir(task_id, bad_job_id, repo_url)

    def _handle_bisect_result_no_release(self, result: Any, task: Dict, task_id: int) -> Dict:
        """Handle bisect result (no repo release, using context manager)"""
        if self._is_task_deleted(task_id):
            return self._deleted_task_result(task_id, 'result handling')

        if result and isinstance(result, dict) and result.get('first_bad_commit'):
            # Success handling logic
            # New flow: Git bisect includes verification, directly mark as verified
            current_time = int(time.time())

            # Extract boundary_verification info (defensive: ensure it is a dict)
            boundary_verification = result.get('boundary_verification') or {}

            # Diagnostic log: check if boundary_verification is empty
            if not boundary_verification:
                logger.warning(f"Task {task_id} boundary_verification is empty, cannot get introduced_errids")
                logger.warning(f"result keys: {list(result.keys()) if isinstance(result, dict) else 'not_dict'}")

            introduced_errids = boundary_verification.get('introduced_errids', []) or []

            # Extract git verification result (contains confidence info)
            git_verification = boundary_verification.get('git_verification') or {}
            parent_job_id = boundary_verification.get('parent_job_id')
            parent_commit = boundary_verification.get('parent_commit')
            head_commit = boundary_verification.get('head_commit')
            verification_status = boundary_verification.get('status')
            verification_passed = boundary_verification.get('verification_passed', False)

            # Extract errid_log_context (error log messages)
            errid_log_context = boundary_verification.get('errid_log_context', {}) or {}
            if errid_log_context:
                logger.info(f"Extracted errid_log_context | task_id: {task_id} | errids: {len(errid_log_context)} with log context")
            else:
                logger.info(f"No errid_log_context | task_id: {task_id}")

            # Extract HEAD check results (py_bisect already completed HEAD detection)
            head_check = boundary_verification.get('head_check') or {}
            head_check_status = head_check.get('status')
            head_check_job_id = boundary_verification.get('head_job_id')
            head_regressed_errids = head_check.get('regressed_errids', []) or []

            if head_check:
                logger.info(f"Extracted HEAD check result | task_id: {task_id} | status: {head_check_status} | regressed: {len(head_regressed_errids)}")
            else:
                logger.info(f"No HEAD check result | task_id: {task_id} | py_bisect may not have run HEAD check")

            # If no introduced_errids but has parent_job_id, try to recalculate
            if not introduced_errids and parent_job_id:
                try:
                    bad_job_id = task.get('bad_job_id')
                    logger.warning(f"No introduced_errids in boundary_verification, trying to recalculate | parent: {parent_job_id} | bad: {bad_job_id}")
                    from verification_consumer import create_verification_consumer
                    vc = create_verification_consumer(self.config)
                    introduced_errids = vc.calculate_errid_diff(str(parent_job_id), str(bad_job_id))
                    logger.info(f"Recalculated {len(introduced_errids)} introduced_errids")
                except Exception as calc_err:
                    logger.error(f"Failed to recalculate introduced_errids: {str(calc_err)}")
                    introduced_errids = []

            logger.info(f"Bisect succeeded | task_id: {task_id} | introduced_errids: {len(introduced_errids)} | boundary_verification: {'present' if boundary_verification else 'absent'}")
            if introduced_errids and len(introduced_errids) <= 5:
                logger.info(f"  Sample introduced_errids: {introduced_errids[:5]}")
            elif not introduced_errids:
                logger.warning(f"Task {task_id} has no introduced_errids | parent_job: {parent_job_id} | parent_commit: {parent_commit}")

            # Extract other useful info (defensive: ensure it is a dict)
            bisect_range = result.get('bisect_range') or {}
            verification_info = result.get('verification') or {}

            # Calculate confidence (based on git verification result)
            confidence = self._calculate_confidence_from_git_verification(
                git_verification, boundary_verification, task_id
            )

            # Determine bisect_status based on verification_status
            # - verified: bisect succeeded and verification passed -> success
            # - failed: bisect found commit but verification failed -> depends on reason
            # - error: verification process error -> wait (re-execute)
            # - None/other: no verification info -> wait (re-execute)
            if verification_status in ('verified', 'success') and verification_passed:
                final_bisect_status = "success"
                final_verification_status = "verified"
                final_verified = True
            else:
                # Verification failed or error
                failed_reason = boundary_verification.get('verification_failed_reason', 'unknown')
                # Read retry_count directly from database field
                retry_count = (task.get('retry_count', 0) or 0) + 1

                # Determine if should mark as failed (no more retries)
                # 1. target_error_id_not_in_introduced: target error_id not in introduced errors list, may be flaky error
                # 2. retry count exceeds 3
                should_mark_failed = False
                existing_j_raw = task.get('j')
                if isinstance(existing_j_raw, str):
                    try:
                        existing_j_raw = json.loads(existing_j_raw) if existing_j_raw else {}
                    except json.JSONDecodeError:
                        existing_j_raw = {}
                existing_j = existing_j_raw if isinstance(existing_j_raw, dict) else {}
                if 'target_error_id_not_in_introduced' in failed_reason:
                    should_mark_failed = True
                    logger.warning(
                        f"Boundary verification failed: target error_id not in introduced list | task_id: {task_id} | "
                        f"may be flaky error, marking as failed"
                    )
                elif retry_count >= 3:
                    should_mark_failed = True
                    logger.warning(
                        f"Boundary verification retry limit reached | task_id: {task_id} | "
                        f"retry_count: {retry_count} | marking as failed"
                    )

                if should_mark_failed:
                    # Mark as failed, no more retries
                    # Merge verification metadata into existing j field to preserve
                    # original commit info (good_commit, bad_commit, etc.)
                    bisect_failed_reason = f"boundary_verification_failed:{failed_reason}"
                    merged_j = {**existing_j,
                        "verification_status": verification_status,
                        "verification_failed_reason": failed_reason,
                        "verification_time": current_time,
                        "first_bad_commit": result.get('first_bad_commit', ''),
                        "boundary_verification": boundary_verification
                    }
                    failed_doc = {
                        "bisect_status": "failed",
                        "last_error": bisect_failed_reason,
                        "retry_count": retry_count,
                        "updated_at": current_time,
                        "j": merged_j
                    }
                    if self._is_task_deleted(task_id):
                        return self._deleted_task_result(task_id, 'failed-result persistence')
                    self.client.update("bisect", task_id, failed_doc)
                    return {
                        'status': 'failed',
                        'id': task_id,
                        'reason': bisect_failed_reason
                    }
                else:
                    # Return to wait for re-execution
                    logger.warning(
                        f"Boundary verification not passed, task returning to wait | task_id: {task_id} | "
                        f"verification_status: {verification_status} | verification_passed: {verification_passed} | "
                        f"reason: {failed_reason} | retry_count: {retry_count}"
                    )

                    # Merge verification metadata into existing j field to preserve
                    # original commit info (good_commit, bad_commit, etc.)
                    merged_j = {**existing_j,
                        "last_verification_status": verification_status,
                        "last_verification_failed_reason": failed_reason,
                        "last_verification_time": current_time
                    }
                    wait_doc = {
                        "bisect_status": "wait",
                        "retry_count": retry_count,
                        "updated_at": current_time,
                        "j": merged_j
                    }
                    if self._is_task_deleted(task_id):
                        return self._deleted_task_result(task_id, 'retry-result persistence')
                    self.client.update("bisect", task_id, wait_doc)
                    return {
                        'status': 'retry',
                        'id': task_id,
                        'reason': f'verification_{verification_status}: {failed_reason}'
                    }

            success_doc = {
                "bisect_status": final_bisect_status,
                "first_bad_commit": result.get('first_bad_commit', '') or '',  # pure SHA
                "first_bad_id": result.get('first_bad_id', '') or '',
                "first_result_root": result.get('bad_result_root', '') or '',
                "bisect_result_root": task.get('bisect_result_root', '') or '',
                "start_time": result.get('start_time', 0) or 0,
                "end_time": result.get('end_time', 0) or 0,
                "last_error": "",  # Clear previous error message
                "updated_at": current_time,
                "j": {
                    # Verification status
                    "verification_status": final_verification_status,
                    "verification_method": "integrated_bisect",
                    "validation_status": "completed",
                    "verified": final_verified,
                    "confidence": confidence,  # dynamically calculated confidence
                    "skip_success_validation": True,

                    # first_bad_commit related fields
                    "first_bad_commit_subject": result.get('first_bad_commit_subject', ''),
                    # change_point: SHA + subject, for display
                    "change_point": result.get('change_point', ''),

                    # boundary_verification full info (from py_bisect)
                    "boundary_verification": boundary_verification,

                    # Quick access fields (avoid deep nesting, extracted from boundary_verification)
                    "introduced_errids": introduced_errids,
                    "introduced_errids_count": len(introduced_errids),
                    "errid_log_context": errid_log_context,
                    "parent_job_id": parent_job_id,
                    "parent_commit": parent_commit,
                    "verification_passed": verification_passed,

                    # HEAD check results (extracted from py_bisect, using same field names as head_validator)
                    "head_check_status": head_check_status,
                    "head_check_commit": head_commit,
                    "head_check_job_id": head_check_job_id,
                    "head_check_at": current_time if head_check_status else None,
                    "head_check_source": "py_bisect" if head_check_status else None,
                    "regressed_errids": head_regressed_errids,
                    "head_check_completed": bool(head_check_status),

                    # bisect_range info (complete object)
                    "bisect_range": bisect_range,
                    # Quick access fields
                    "start_commit": bisect_range.get('start_commit'),
                    "end_commit": bisect_range.get('end_commit'),

                    # verification info (from py_bisect, complete object)
                    "verification_info": verification_info,
                    # Quick access fields
                    "verification_reason": verification_info.get('reason'),
                    "verification_confidence": verification_info.get('confidence'),

                    # job reuse statistics (from py_bisect)
                    "job_request_count": result.get('job_request_count', 0),
                    "job_reused_count": result.get('job_reused_count', 0),
                    "job_reused_rate": result.get('job_reused_rate', 0.0)
                }
            }

            if self._is_task_deleted(task_id):
                return self._deleted_task_result(task_id, 'success persistence')
            self.client.update("bisect", task_id, success_doc)

            if self._is_task_deleted(task_id):
                return self._deleted_task_result(task_id, 'success side effects')

            # Generate notification and records
            try:
                from bisect_utils import write_regression_record
                write_regression_record(
                    task_id=task_id,
                    bad_job_id=task.get('bad_job_id'),
                    first_bad_commit=result.get('first_bad_commit'),
                    git_url=task.get('git_url'),
                    error_id=task.get('error_id'),
                    bisect_metric=task.get('bisect_metric')
                )
            except Exception as e:
                logger.warning(f"Failed to write regression record: {str(e)}")

            # Report generation logic:
            # - If py_bisect completed HEAD check (head_check_completed = true), generate report immediately
            # - If HEAD check not completed, report generation deferred to head_validator
            if head_check_status:
                # py_bisect completed HEAD check, generate report immediately
                logger.info(f"py_bisect completed HEAD check | task_id: {task_id} | generating report immediately")
                try:
                    # Re-query task to get updated full info (including j field)
                    updated_tasks = self.client.sql_select(f"SELECT * FROM bisect WHERE id = {task_id}")
                    if updated_tasks:
                        updated_task = updated_tasks[0]

                        # Get job info for report
                        bad_job_id = task.get('bad_job_id')
                        job_info = None
                        if bad_job_id:
                            try:
                                job_query = f"SELECT * FROM jobs WHERE id = {int(bad_job_id)} LIMIT 1"
                                job_results = self.client.sql_select(job_query)
                                if job_results and len(job_results) > 0:
                                    job_info = job_results[0]
                            except Exception as e:
                                logger.warning(f"Failed to get job info | job_id: {bad_job_id} | error: {str(e)}")

                        # Generate report
                        report_path = self.notification_writer.write_bisect_success_report(
                            updated_task,
                            job_info=job_info,
                            introduced_errids=introduced_errids
                        )
                        if report_path:
                            logger.info(f"Bisect success report generated | task_id: {task_id} | path: {report_path}")
                        else:
                            logger.warning(f"Failed to generate bisect success report | task_id: {task_id}")
                    else:
                        logger.warning(f"Cannot get updated task info | task_id: {task_id}")
                except Exception as e:
                    logger.error(f"Exception generating bisect success report | task_id: {task_id} | error: {str(e)}")
                    logger.error(traceback.format_exc())
            else:
                # py_bisect did not complete HEAD check, report generation deferred to head_validator
                logger.info(f"py_bisect did not complete HEAD check | task_id: {task_id} | report generation deferred to head_validator")

            # Note: similar task marking and promotion is now handled in task_processor._cluster_and_select_tasks
            # No longer calling _promote_pending_verification_tasks here

            logger.info(f"Task completed successfully (with integrated verification) | ID: {task_id} | first_bad_commit: {result.get('first_bad_commit')}")
            return {
                'status': 'success',
                'id': task_id,
                'first_bad_commit': result.get('first_bad_commit', '')
            }

        else:
            # Failure handling logic
            error_msg = "Bisect execution failed"
            if isinstance(result, dict) and result.get('error'):
                error_msg = result.get('error')

            # Ensure failed task also has correct bisect_result_root
            bisect_result_root = task.get('bisect_result_root', '')
            if not bisect_result_root:
                # If not set, regenerate
                bisect_result_root = self._generate_task_path(self.config, task)
                logger.info(f"Regenerated bisect_result_root for failed task: {bisect_result_root}")

            fail_doc = {
                "bisect_status": "failed",
                "last_error": error_msg,
                "bisect_result_root": bisect_result_root,
                "updated_at": int(time.time())
            }

            if self._is_task_deleted(task_id):
                return self._deleted_task_result(task_id, 'failure persistence')
            self.client.update("bisect", task_id, fail_doc)
            logger.error(f"Task execution failed | ID: {task_id} | reason: {error_msg}")
            return {'status': 'failed', 'error': error_msg, 'id': task_id}

    def _handle_performance_bisect_result(self, result: Any, task: Dict, task_id: int) -> Dict:
        """Handle performance bisect result

        Performance bisect uses midpoint algorithm, verification result format:
        - verified: whether verification passed
        - bad_commit_verification: bad commit sample verification
        - parent_commit_verification: parent commit sample verification
        - confidence: overall confidence
        """
        if self._is_task_deleted(task_id):
            return self._deleted_task_result(task_id, 'performance result handling')

        current_time = int(time.time())

        if result and isinstance(result, dict) and result.get('first_bad_commit'):
            # Success: record performance bisect result
            first_bad_commit = result.get('first_bad_commit', '')
            bisect_metric = task.get('bisect_metric', '')

            # Extract verification info
            verified = result.get('verified', False)
            confidence = result.get('confidence', 0.0)
            parent_commit = result.get('parent_commit', '')
            verification_reason = result.get('reason', '')

            # Extract bad_commit verification details
            bad_commit_verification = result.get('bad_commit_verification') or {}
            parent_commit_verification = result.get('parent_commit_verification') or {}

            # Extract bisect_range info
            bisect_range = result.get('bisect_range') or {}

            # Calculate confidence level from confidence score
            if confidence >= 0.9:
                confidence_level = 'high'
            elif confidence >= 0.5:
                confidence_level = 'medium'
            else:
                confidence_level = 'low'

            # Determine final status
            if verified and confidence >= 0.5:
                final_status = "success"
            else:
                final_status = "success"  # Still mark as success, but confidence may be low

            success_doc = {
                "bisect_status": final_status,
                "first_bad_commit": first_bad_commit,
                "first_bad_id": result.get('first_bad_id', '') or '',
                "first_result_root": result.get('bad_result_root', '') or '',
                "bisect_result_root": task.get('bisect_result_root', '') or '',
                "start_time": result.get('start_time', 0) or 0,
                "end_time": result.get('end_time', 0) or 0,
                "last_error": "",
                "updated_at": current_time,
                "j": {
                    # Performance bisect type identifier
                    "bisect_type": "performance",

                    # Commit info
                    "first_bad_commit_subject": result.get('first_bad_commit_subject', ''),
                    "change_point": result.get('change_point', ''),
                    "change_description": result.get('change_description', ''),
                    "parent_commit": parent_commit,

                    # Verification status
                    "verified": verified,
                    "confidence": confidence,
                    "confidence_level": confidence_level,
                    "verification_reason": verification_reason,
                    "verification_status": "completed",
                    "verification_method": "performance_midpoint",

                    # bad commit verification details
                    "bad_commit_verification": bad_commit_verification,

                    # parent commit verification details
                    "parent_commit_verification": parent_commit_verification,

                    # bisect_range info
                    "bisect_range": bisect_range,
                    "start_commit": bisect_range.get('start_commit'),
                    "end_commit": bisect_range.get('end_commit'),

                    # job reuse statistics
                    "job_request_count": result.get('job_request_count', 0),
                    "job_reused_count": result.get('job_reused_count', 0),
                    "job_reused_rate": result.get('job_reused_rate', 0.0)
                }
            }

            if self._is_task_deleted(task_id):
                return self._deleted_task_result(task_id, 'performance success persistence')
            self.client.update("bisect", task_id, success_doc)

            if self._is_task_deleted(task_id):
                return self._deleted_task_result(task_id, 'performance success side effects')

            # Generate notification and records
            try:
                from bisect_utils import write_regression_record
                write_regression_record(
                    task_id=task_id,
                    bad_job_id=task.get('bad_job_id'),
                    first_bad_commit=first_bad_commit,
                    git_url=task.get('git_url'),
                    error_id=None,
                    bisect_metric=bisect_metric
                )
            except Exception as e:
                logger.warning(f"Failed to write performance regression record: {str(e)}")

            logger.info(f"Performance bisect succeeded | task_id: {task_id} | metric: {bisect_metric} | "
                       f"first_bad_commit: {first_bad_commit[:12] if first_bad_commit else 'N/A'} | "
                       f"verified: {verified} | confidence: {confidence:.2f}")

            return {
                'status': 'success',
                'id': task_id,
                'first_bad_commit': first_bad_commit,
                'bisect_metric': bisect_metric,
                'verified': verified,
                'confidence': confidence
            }

        else:
            # Failure handling
            error_msg = "Performance bisect execution failed"
            if isinstance(result, dict) and result.get('error'):
                error_msg = result.get('error')

            bisect_result_root = task.get('bisect_result_root', '')
            if not bisect_result_root:
                bisect_result_root = self._generate_task_path(self.config, task)

            fail_doc = {
                "bisect_status": "failed",
                "last_error": error_msg,
                "bisect_result_root": bisect_result_root,
                "updated_at": current_time
            }

            if self._is_task_deleted(task_id):
                return self._deleted_task_result(task_id, 'performance failure persistence')
            self.client.update("bisect", task_id, fail_doc)
            logger.error(f"Performance bisect failed | task_id: {task_id} | reason: {error_msg}")
            return {'status': 'failed', 'error': error_msg, 'id': task_id}

    def _handle_bisect_result(self, result: Any, task: Dict, task_id: int, repo_dir: str, job_dir: str) -> Dict:
        """Handle bisect result

        Note: performance/functional tasks do not support verifying status, mark as success once first_bad_commit exists
        But need to save confidence info for external analysis
        """
        if result and isinstance(result, dict) and result.get('first_bad_commit'):
            # Extract verification info
            verified = result.get('verified', False)
            confidence = result.get('confidence', 0)
            confidence_level = result.get('confidence_level', 'unknown')
            verification_reason = result.get('verification_reason', '')
            verification_status = result.get('verification_status', '')

            # Performance/functional tasks: mark as success once first_bad_commit is found
            # Save complete verification info regardless of confidence level for external analysis
            bisect_status = "success"

            # Print different log levels based on confidence
            if verified or confidence >= 0.8 or confidence_level in ['high', 'medium']:
                logger.info(
                    f"Bisect completed (high confidence) | task_id: {task_id} | "
                    f"commit: {result.get('first_bad_commit', '')[:12]} | "
                    f"verified: {verified} | confidence: {confidence} | level: {confidence_level}"
                )
            else:
                logger.warning(
                    f"Bisect completed (low confidence) | task_id: {task_id} | "
                    f"commit: {result.get('first_bad_commit', '')[:12]} | "
                    f"verified: {verified} | confidence: {confidence} | level: {confidence_level} | "
                    f"reason: {verification_reason} | "
                    f"manual review recommended"
                )

            # Build update document, save complete verification info
            success_doc = {
                "bisect_status": bisect_status,
                "first_bad_commit": result.get('first_bad_commit', '') or '',
                "first_bad_id": result.get('first_bad_id', '') or '',
                "first_result_root": result.get('bad_result_root', '') or '',
                "bisect_result_root": task.get('bisect_result_root', '') or '',
                "start_time": result.get('start_time', 0) or 0,
                "end_time": result.get('end_time', 0) or 0,
                "last_error": "",  # Clear previous error message
                "updated_at": int(time.time()),
                "j": {
                    "verified": verified,
                    "confidence": confidence,
                    "confidence_level": confidence_level,
                    "verification_reason": verification_reason,
                    "verification_status": verification_status or "completed"
                }
            }

            # Release repository back to pool
            try:
                if os.path.exists(repo_dir):
                    self.repo_manager.release_repo_dir(repo_dir)
                    logger.info(f"Task repo released back to pool | task_id: {task_id} | repo_dir: {repo_dir}")
            except Exception as e:
                logger.error(f"Error releasing task repo, falling back to deletion: {str(e)}")
                try:
                    if os.path.exists(job_dir):
                        shutil.rmtree(job_dir)
                except OSError:
                    pass

            self.client.update("bisect", task_id, success_doc)
            logger.info(
                f"Task completed | ID: {task_id} | status: {bisect_status} | "
                f"commit: {result.get('first_bad_commit', '')[:12]} | "
                f"confidence: {confidence}"
            )
            return {
                'status': bisect_status,
                'id': task_id,
                'first_bad_commit': result.get('first_bad_commit', ''),
                'verified': verified,
                'confidence': confidence
            }

        else:
            # Failure handling logic
            error_msg = "Bisect execution failed"
            if isinstance(result, dict) and result.get('error'):
                error_msg = result.get('error')

            # Ensure failed task also has correct bisect_result_root
            bisect_result_root = task.get('bisect_result_root', '')
            if not bisect_result_root:
                # If not set, regenerate
                bisect_result_root = self._generate_task_path(self.config, task)
                logger.info(f"Regenerated bisect_result_root for failed task: {bisect_result_root}")

            fail_doc = {
                "bisect_status": "failed",
                "last_error": error_msg,
                "bisect_result_root": bisect_result_root,
                "updated_at": int(time.time())
            }

            # Release repository back to pool on failure
            try:
                if os.path.exists(repo_dir):
                    self.repo_manager.release_repo_dir(repo_dir)
                    logger.info(f"Failed task repo released back to pool | repo_dir: {repo_dir}")
            except Exception as e:
                logger.error(f"Error releasing failed task repo, falling back to deletion: {str(e)}")
                try:
                    if os.path.exists(job_dir):
                        shutil.rmtree(job_dir)
                except OSError:
                    pass

            self.client.update("bisect", task_id, fail_doc)
            logger.error(f"Task execution failed | ID: {task_id} | reason: {error_msg}")
            return {'status': 'failed', 'error': error_msg, 'id': task_id}

    @staticmethod
    def _generate_task_path(config: Dict, task: Dict) -> str:
        """Generate task path"""
        repo_name = extract_repo_name_from_url(task.get('git_url'))

        # Generate appropriate path identifier for different task types
        task_identifier = ""
        if task.get('error_id'):
            task_identifier = hashlib.md5(task['error_id'].encode()).hexdigest()[:8]
        elif task.get('bisect_metric'):
            task_identifier = hashlib.md5(task['bisect_metric'].encode()).hexdigest()[:8]
        else:
            task_identifier = "unknown"

        result_base = os.environ.get('RESULT_DIR', '/result/bisect')
        path = os.path.join(
            result_base,
            'results',
            repo_name,
            datetime.now().strftime("%Y-%m-%d"),
            str(task['bad_job_id']),
            task_identifier,
            str(task['id'])
        )
        os.makedirs(path, exist_ok=True, mode=0o755)
        return os.path.abspath(path)



# Simplified consumer factory function
def create_consumer(config: Dict) -> BisectConsumer:
    """Create consumer instance"""
    client = ManticoreClient(config.get('manticore_host', 'http://localhost:9308'))
    return BisectConsumer(client, config)
