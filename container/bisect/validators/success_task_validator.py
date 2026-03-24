#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Validator for successful/reused bisect tasks.

It verifies boundary conditions (parent vs first_bad_commit) and computes
introduced errids so reused outcomes can be trusted and tracked.
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

sys.path.append((os.environ['LKP_SRC']) + '/sbin/bisect/')
from lkp_bisect.db.manticore import ManticoreClient
from lkp_bisect.core.git_bisect import GitBisect

# Reuse shared verification logic
from verification_consumer import VerificationConsumer

# Commit-time service client for parent-commit lookup
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/services/commit_time_service')
from client import CommitTimeClient
from bisect_utils import (
        mark_similar_wait_tasks_for_verification,
        mark_introduced_errid_tasks_for_verification
        )
from errid_intelligence import ErridIntelligence

class SuccessTaskValidator(VerificationConsumer):
    """Validate success/reuse tasks and persist verification artifacts."""
    _TERMINAL_VERIFICATION_JOB_HEALTH = {
        'cancel',
        'terminate',
        'abort',
        'abort_invalid',
        'abort_wait',
        'abort_provider',
    }

    @classmethod
    def _is_terminal_failed_health(cls, health: Any) -> bool:
        value = str(health or '').strip().lower()
        if not value:
            return False
        if value.startswith('timeout_'):
            return True
        return value in cls._TERMINAL_VERIFICATION_JOB_HEALTH

    def __init__(self, client: ManticoreClient, config: Dict):
        """Initialize success-task validator."""
        super().__init__(client, config)

        # Validation settings
        self.validation_batch_size = config.get('verification_batch_size', 200)
        self.validation_interval = config.get('validation_interval', 3600)

        # Initialize GitBisect instance for job submission
        self.bisect_instance = GitBisect(logger)

        # Initialize CommitTimeClient for getting parent commits via API
        commit_time_service_url = config.get('commit_time_service_url', 'http://localhost:8765')
        self.commit_time_client = CommitTimeClient(service_url=commit_time_service_url)

        logger.info(
            f"SuccessTaskValidator initialized | "
            f"batch_size: {self.validation_batch_size} | "
            f"interval: {self.validation_interval}s | "
            f"commit_time_service: {commit_time_service_url}"
        )

    def scan_unverified_tasks(self, limit: int = None) -> List[Dict]:
        """
        Scan unverified tasks in verifying/pending_verification states.

        Representative success tasks from full bisect runs do not need this.
        This scan focuses on reused tasks that still need boundary checks.

        Args:
            limit: maximum tasks to return (default: validation_batch_size)

        Returns:
            list of tasks to validate
        """
        try:
            batch_size = limit or self.validation_batch_size
            current_time = int(time.time())

            # query: query verifying status tasks
            # JSON filtering is done in Python to avoid Manticore JSON syntax limitations
            sql_query = f"""
                SELECT id, bad_job_id, error_id, bisect_status, git_url,
                       updated_at, submit_time, j
                FROM bisect
                WHERE bisect_status = 'verifying'
                ORDER BY updated_at DESC
                LIMIT {batch_size}
            """

            logger.info(f"scanno verifying tasks found | batch_size: {batch_size}")
            results = self.client.sql_select(sql_query)

            if not results:
                logger.info("no verifying tasks found")
                return []

            logger.info(f"SQL query returned {len(results)} no verifying tasks found")

            # Python :  related_task_id verifycompletedtask
            filtered_tasks = []
            tasks_without_related_id = []  #  related_task_id task

            for task in results:
                task_id = task.get('id')
                j_field = task.get('j', {})

                #  j 
                if isinstance(j_field, str):
                    try:
                        j_field = json.loads(j_field) if j_field else {}
                    except Exception:
                        j_field = {}

                # check conditions
                related_task_id = j_field.get('related_task_id')
                if not related_task_id:
                    logger.warning(f"verifying task related_task_id, reset wait | task_id: {task_id}")
                    tasks_without_related_id.append(task_id)
                    continue

                # Skip tasks already verified.
                verification_status = j_field.get('verification_status')
                if verification_status == 'verified':
                    logger.debug(f"skip task {task_id}: already verified (verification_status=verified)")
                    continue

                # skip already verified by py_bisect
                if j_field.get('verified_by_py_bisect') is True:
                    logger.debug(f"skip task {task_id}: already verified by py_bisect")
                    continue

                # skipsubmitverification job
                verification_jobs = j_field.get('verification_jobs', {})
                if verification_jobs and verification_jobs.get('status') == 'retry_pending':
                    next_retry_at = verification_jobs.get('next_retry_at') or j_field.get('verification_submit_next_retry_at')
                    try:
                        next_retry_at = int(next_retry_at) if next_retry_at is not None else None
                    except (TypeError, ValueError):
                        next_retry_at = None
                    if next_retry_at and next_retry_at > current_time:
                        logger.debug(
                            f"skip task {task_id}: retry backoff | next_retry_in: {next_retry_at - current_time}s"
                        )
                        continue
                if verification_jobs and verification_jobs.get('status') == 'submitted':
                    logger.debug(f"skip task {task_id}: verification job already submitted")
                    continue

                filtered_tasks.append(task)

            # reset related_task_id task wait( verifying status)
            if tasks_without_related_id:
                self._reset_tasks_to_wait(tasks_without_related_id, "no_related_task_id")

            logger.info(
                f" {len(filtered_tasks)} task | "
                f": {len(results)} | : {len(results) - len(filtered_tasks)} | "
                f"resetwait: {len(tasks_without_related_id)}"
            )

            return filtered_tasks

        except Exception as e:
            logger.error(f"scan verification tasks failed: {str(e)}")
            logger.error(traceback.format_exc())
            return []


    def group_tasks_by_repo(self, tasks: List[Dict]) -> Dict[str, List[Dict]]:
        """
        repotask

        Args:
            tasks: verification tasklist

        Returns:
             git_url taskdict
        """
        tasks_by_repo = defaultdict(list)

        for task in tasks:
            task_id = task['id']
            bisect_status = task.get('bisect_status')
            git_url = task.get('git_url')

            # task git_url, taskget
            if not git_url:
                try:
                    j_field = task.get('j', {})
                    if isinstance(j_field, str):
                        j_field = json.loads(j_field)

                    related_task_id = j_field.get('related_task_id')

                    if related_task_id:
                        # querytask git_url
                        related_task = self._get_related_task(str(related_task_id))
                        if related_task:
                            git_url = related_task.get('git_url')

                except Exception as e:
                    logger.warning(f"get task git_url failed | task_id: {task_id} | error: {str(e)}")

            #  git_url, skip
            if not git_url:
                logger.warning(f"task git_url, skip | task_id: {task_id} | status: {bisect_status}")
                continue

            tasks_by_repo[git_url].append(task)

        return tasks_by_repo

    def batch_submit_verification_jobs(
        self, repo_tasks: List[Dict], git_url: str, repo_manager=None
    ) -> Dict[str, int]:
        """
        submitverification job

         CommitTimeService API getsubmit,  clone repo.

        Args:
            repo_tasks: task list for one repo (verifying status only)
            git_url: repo URL
            repo_manager: , 

        Returns:
            {'submitted': submitsuccess, 'failed': failed}
        """
        submitted_count = 0
        failed_count = 0
        skipped_count = 0

        logger.info(f"start submit verification jobs | repo: {git_url[:60]}... | tasks: {len(repo_tasks)}")

        # Step 1: query task status( N+1 query)
        related_task_ids = set()
        for task in repo_tasks:
            j_field = task.get('j', {})
            if isinstance(j_field, str):
                j_field = json.loads(j_field)

            related_task_id = j_field.get('related_task_id')
            if related_task_id:
                related_task_ids.add(str(related_task_id))

        # query
        related_tasks_map = {}
        if related_task_ids:
            try:
                ids_str = ','.join(related_task_ids)
                batch_query = f"""
                    SELECT id, bisect_status, first_bad_commit, git_url
                    FROM bisect
                    WHERE id IN ({ids_str})
                """
                batch_results = self.client.sql_select(batch_query)

                if batch_results:
                    for result in batch_results:
                        related_tasks_map[str(result['id'])] = result

                    logger.info(f"query {len(related_task_ids)} task | : {len(related_tasks_map)} ")
            except Exception as e:
                logger.error(f"query related tasks failed: {str(e)}")

        # Step 2: submit task
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

            # checksubmit
            verification_jobs = j_field.get('verification_jobs', {})
            if verification_jobs and verification_jobs.get('status') in ['submitted', 'timeout']:
                skipped_count += 1
                logger.debug(f"verification job already submitted, skip | task_id: {task_id}")
                continue

            # gettask
            related_task_id = j_field.get('related_task_id')
            if not related_task_id:
                logger.warning(f"verifying task related_task_id | ID: {task_id}")
                failed_count += 1
                continue

            related_task = related_tasks_map.get(str(related_task_id))
            if not related_task:
                related_task = self._get_related_task(str(related_task_id))
                if not related_task:
                    logger.warning(f"tasknot found | ID: {task_id} | related: {related_task_id}")
                    failed_count += 1
                    continue

            related_status = related_task.get('bisect_status')

            if related_status == 'failed':
                logger.warning(f"taskfailed, skip | ID: {task_id} | related: {related_task_id}")
                self._mark_task_failed(task_id, related_task_id, "related_task_failed")
                failed_count += 1
                continue

            if related_status != 'success':
                logger.debug(f"tasksuccess, skip | ID: {task_id} | related: {related_task_id} | status: {related_status}")
                skipped_count += 1
                continue

            # Safety guard: verification task and related successful task must use the same repo.
            related_git_url = (related_task.get('git_url') or '').strip()
            current_git_url = (git_url or '').strip()
            if related_git_url and current_git_url and related_git_url != current_git_url:
                reason = (
                    f"related_task_repo_mismatch: current={current_git_url[:80]} "
                    f"related={related_git_url[:80]}"
                )
                logger.error(
                    f"repo mismatch, skip verification submit | "
                    f"task_id: {task_id} | related_task_id: {related_task_id} | {reason}"
                )
                self._mark_task_failed(task_id, related_task_id, reason)
                failed_count += 1
                continue

            first_bad_commit = related_task.get('first_bad_commit')
            if not first_bad_commit:
                logger.warning(f"task first_bad_commit | ID: {task_id} | related: {related_task_id}")
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
            f"taskcompleted | submit: {len(tasks_to_submit)} | "
            f"skip: {skipped_count} | failed: {failed_count}"
        )

        if not tasks_to_submit:
            return {'submitted': 0, 'failed': failed_count}

        # Step 3: submit task( API getsubmit,  clone repo)
        logger.info(f"startsubmit {len(tasks_to_submit)} task( CommitTimeService API getsubmit)")

        for task_info in tasks_to_submit:
            task_id = task_info['task_id']
            first_bad_commit = task_info['first_bad_commit']
            error_id = task_info['error_id']
            bad_job_id = task_info['bad_job_id']
            related_task_id = task_info.get('related_task_id', '')

            try:
                # submitverification job( API getsubmit)
                result = self._submit_verification_jobs_with_shared_repo(
                    task_id=task_id,
                    bad_job_id=bad_job_id,
                    first_bad_commit=first_bad_commit,
                    git_url=git_url,
                    error_id=error_id,
                    repo_dir=""  # , 
                )

                status = result.get('status')
                if status == 'success':
                    submitted_count += 1
                    logger.info(
                        f"[OK] verification job already submitted | task_id: {task_id} | "
                        f"parent_job: {result['parent_job_id']} | "
                        f"candidate_job: {result['candidate_job_id']}"
                    )
                elif status == 'retry':
                    skipped_count += 1
                    error = result.get('error', '')
                    logger.warning(
                        f"[RETRY] defer verification submit | task_id: {task_id} | "
                        f"reason: {error}"
                    )
                    self._schedule_verification_retry(task_id, related_task_id, error)
                else:
                    failed_count += 1
                    error = result.get('error', '')
                    logger.error(f"[ERR] submitverification jobfailed | task_id: {task_id} | error: {error}")
                    # taskfailed, duplicate
                    self._mark_task_failed(task_id, related_task_id, f"verification_submit_failed: {error}")

            except Exception as e:
                failed_count += 1
                logger.error(f"[ERR] submitverification jobexception | task_id: {task_id} | error: {str(e)}")
                logger.error(traceback.format_exc())
                # taskfailed, duplicate
                self._mark_task_failed(task_id, related_task_id, f"verification_submit_exception: {str(e)}")

        logger.info(
            f"submitcompleted | repo: {git_url[:60]}... | "
            f"submitted: {submitted_count} | failed: {failed_count} | skipped: {skipped_count}"
        )

        return {'submitted': submitted_count, 'failed': failed_count}

    def _submit_verification_jobs_with_shared_repo(
        self, task_id: int, bad_job_id: str, first_bad_commit: str,
        git_url: str, error_id: str, repo_dir: str
    ) -> Dict:
        """
        Submit verification jobs using shared repo (no duplicate clone)

        Args:
            task_id: task ID
            bad_job_id: job ID
            first_bad_commit:  commit
            git_url: repo URL
            error_id: error ID
            repo_dir: repo(, )

        Returns:
            {'status': 'success', 'parent_job_id': xxx, 'candidate_job_id': xxx}
        """
        try:
            current_time = int(time.time())

            logger.info(
                f"submitverification job | task_id: {task_id} | "
                f"candidate: {first_bad_commit[:12]} | git_url: {git_url[:60]}..."
            )

            #  CommitTimeService API getsubmit( clone repo)
            parent_commit = self.commit_time_client.get_parent_commit(git_url, first_bad_commit)

            if not parent_commit:
                error_msg = f"failed_to_get_parent_commit_via_api: commit={first_bad_commit[:12]}"
                logger.error(f" API getsubmitfailed | task_id: {task_id} | commit: {first_bad_commit[:12]}")
                return {
                    'status': 'retry',
                    'task_id': task_id,
                    'error': error_msg
                }

            logger.debug(f"submitgetsuccess(via API)| parent: {parent_commit[:12]}")

            #  GitBisect instancesubmitverification job
            # 1. submitsubmitverification job
            try:
                job_config_parent = self.bisect_instance.init_job_content(bad_job_id)

                # commitsubmit
                if 'ss' in job_config_parent and 'linux' in job_config_parent['ss']:
                    job_config_parent['ss']['linux']['commit'] = parent_commit
                elif 'program' in job_config_parent and 'makepkg' in job_config_parent['program']:
                    job_config_parent['program']['makepkg']['commit'] = parent_commit
                else:
                    return {'status': 'failed', 'error': 'unrecognized_job_structure'}

                parent_job_id, parent_result_root, *_ = self.bisect_instance.submit_job(job_config_parent)
                logger.debug(f"job submitted | job_id: {parent_job_id} | commit: {parent_commit[:12]}")

            except Exception as e:
                logger.error(f"submit job failed | error: {str(e)}")
                return {'status': 'failed', 'error': f'submit_parent_failed: {str(e)}'}

            # 2. submitsubmitverification job
            try:
                job_config_candidate = self.bisect_instance.init_job_content(bad_job_id)

                # commitsubmit
                if 'ss' in job_config_candidate and 'linux' in job_config_candidate['ss']:
                    job_config_candidate['ss']['linux']['commit'] = first_bad_commit
                elif 'program' in job_config_candidate and 'makepkg' in job_config_candidate['program']:
                    job_config_candidate['program']['makepkg']['commit'] = first_bad_commit
                else:
                    return {'status': 'failed', 'error': 'unrecognized_job_structure'}

                candidate_job_id, candidate_result_root, *_ = self.bisect_instance.submit_job(job_config_candidate)
                logger.debug(f"job submitted | job_id: {candidate_job_id} | commit: {first_bad_commit[:12]}")

            except Exception as e:
                logger.error(f"submit job failed | error: {str(e)}")
                return {'status': 'failed', 'error': f'submit_candidate_failed: {str(e)}'}

            # 3. job
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
            logger.error(f"submitverification jobexception | task_id: {task_id} | error: {str(e)}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': str(e)}

    def _reset_tasks_to_wait(self, task_ids: List[int], reason: str):
        """
        taskreset wait status

        Args:
            task_ids: taskIDlist
            reason: resetreason
        """
        if not task_ids:
            return

        current_time = int(time.time())
        reset_count = 0

        for task_id in task_ids:
            try:
                # Fetch existing j field to merge (avoid destroying commit info)
                existing_j = {}
                try:
                    task_row = self.client.sql_select(f"SELECT j FROM bisect WHERE id = {task_id} LIMIT 1")
                    if task_row:
                        existing_j = task_row[0].get('j', {}) or {}
                        if isinstance(existing_j, str):
                            import json
                            existing_j = json.loads(existing_j) if existing_j else {}
                except Exception:
                    pass
                reset_doc = {
                    "bisect_status": "wait",
                    "updated_at": current_time,
                    "j": {**existing_j,
                        "reset_from_verifying": True,
                        "reset_reason": reason,
                        "reset_timestamp": current_time
                    }
                }
                self.client.update("bisect", task_id, reset_doc)
                reset_count += 1
            except Exception as e:
                logger.error(f"resettask wait failed | task_id: {task_id} | error: {str(e)}")

        logger.info(f"reset {reset_count}/{len(task_ids)} task wait | reason: {reason}")

    def _mark_task_failed(self, task_id: int, related_task_id: str, reason: str):
        """taskfailed()"""
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
            logger.error(f"mark task failed exception | task_id: {task_id} | error: {str(e)}")

    def _schedule_verification_retry(self, task_id: int, related_task_id: str, reason: str):
        """Schedule verification submit retry with simple exponential backoff."""
        try:
            current_time = int(time.time())
            existing_j = {}
            try:
                task_row = self.client.sql_select(f"SELECT j FROM bisect WHERE id = {task_id} LIMIT 1")
                if task_row:
                    existing_j = task_row[0].get('j', {}) or {}
                    if isinstance(existing_j, str):
                        existing_j = json.loads(existing_j) if existing_j else {}
            except Exception:
                pass

            retry_count = int(existing_j.get('verification_submit_retry_count', 0) or 0) + 1
            # 5m, 10m, 20m ... cap at 1h
            backoff_seconds = min(3600, 300 * (2 ** (retry_count - 1)))
            next_retry_at = current_time + backoff_seconds

            verification_jobs = existing_j.get('verification_jobs', {})
            if not isinstance(verification_jobs, dict):
                verification_jobs = {}
            verification_jobs.update({
                "status": "retry_pending",
                "failure_reason": reason,
                "retry_count": retry_count,
                "last_retry_at": current_time,
                "next_retry_at": next_retry_at
            })

            retry_doc = {
                "bisect_status": "verifying",
                "updated_at": current_time,
                "j": {**existing_j,
                    "related_task_id": str(related_task_id),
                    "verification_status": "retry_pending",
                    "verification_submit_last_error": reason,
                    "verification_submit_retry_count": retry_count,
                    "verification_submit_last_retry_at": current_time,
                    "verification_submit_next_retry_at": next_retry_at,
                    "verification_jobs": verification_jobs
                }
            }
            self.client.update("bisect", task_id, retry_doc)
            logger.info(
                f"scheduled verification retry | task_id: {task_id} | "
                f"retry_count: {retry_count} | next_retry_in: {backoff_seconds}s"
            )
        except Exception as e:
            logger.error(f"schedule verification retry failed | task_id: {task_id} | error: {str(e)}")

    def check_verification_results_once(self, repo_manager=None, limit: int = 500, timeout_hours: int = 24):
        """
        checkverification job(, )

        Args:
            repo_manager: SharedRepoManager instance, filecheck
            limit: checktask
            timeout_hours: verification jobtimeout(), default 24 

        Returns:
            dict: stats {'checked': N, 'completed': N, 'failed': N, 'timeout': N, 'waiting': N, 'skipped': N}
        """
        errid_intelligence = ErridIntelligence()
        try:
            # query verification jobs (exclude completed/failed)
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
                logger.debug("checkverification job")
                return {'checked': 0, 'completed': 0, 'failed': 0, 'timeout': 0, 'waiting': 0, 'skipped': 0}

            logger.info(f"check {len(pending_jobs)} verification job")

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

                    # checktimeout( submit_time, not found updated_at )
                    submitted_time = verification_jobs.get('submit_time')
                    if not submitted_time:
                        submitted_time = job.get('updated_at', 0)

                    if submitted_time and (current_time - submitted_time) > timeout_seconds:
                        logger.warning(f"verification jobtimeout | task_id: {task_id} | : {(current_time - submitted_time)/3600:.1f} ")
                        self.mark_verification_timeout(task_id, reason="timeout_exceeded")
                        timeout_count += 1
                        continue

                    # Check verification job status.
                    parent_job_id = verification_jobs.get('parent_job_id')
                    candidate_job_id = verification_jobs.get('candidate_job_id')
                    parent_result_root = verification_jobs.get('parent_result_root')
                    candidate_result_root = verification_jobs.get('candidate_result_root')
                    error_id = verification_jobs.get('error_id', '')

                    if not parent_job_id or not candidate_job_id:
                        logger.warning(f"verification job job_id | task_id: {task_id} |  wait")

                        # Mark as wait, return to queue for reprocessing
                        # Preserve existing j field (commit info) while clearing verification state
                        existing_j = {}
                        try:
                            task_row = self.client.sql_select(f"SELECT j FROM bisect WHERE id = {task_id} LIMIT 1")
                            if task_row:
                                existing_j = task_row[0].get('j', {}) or {}
                                if isinstance(existing_j, str):
                                    import json
                                    existing_j = json.loads(existing_j) if existing_j else {}
                                # Remove old verification keys but keep commit info
                                for vk in ('verification_status', 'verification_jobs', 'verification_passed'):
                                    existing_j.pop(vk, None)
                        except Exception:
                            pass
                        reset_doc = {
                            "bisect_status": "wait",
                            "updated_at": current_time,
                            "j": existing_j
                        }

                        self.client.update("bisect", task_id, reset_doc)
                        failed_count += 1
                        continue

                    # Check status via GitBisect instance.
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

                    # jobcompleted, 
                    if (parent_completed and candidate_completed):
                        logger.info(f"verification jobcompleted | task_id: {task_id} | start")

                        # checksubmitsubmiterrorstatus
                        parent_bad_job = self.bisect_instance.init_job_content(parent_job_id)
                        self.bisect_instance.is_build_task = self.bisect_instance._detect_build_task(parent_bad_job)
                        # _check_error_id  (status, certainty, reason) 
                        parent_status, _, _ = self.bisect_instance._check_error_id(parent_stats, error_id, parent_health, parent_result_root)
                        candidate_status, _, _ = self.bisect_instance._check_error_id(candidate_stats, error_id, candidate_health, candidate_result_root)

                        verification_passed = (parent_status == 'good' and candidate_status == 'bad')
                        logger.info(
                            f"verify | task_id: {task_id} | "
                            f"parent: {parent_status} | candidate: {candidate_status} | "
                            f"passed: {verification_passed}"
                        )
                    elif not parent_completed or not candidate_completed:
                        # jobcompleted, checkjob(health  'job_not_found'  None )
                        #  6 job, job
                        job_lost = False
                        lost_reason = ""
                        terminal_failure = False
                        terminal_reason = ""

                        parent_health_norm = str(parent_health or '').strip().lower()
                        candidate_health_norm = str(candidate_health or '').strip().lower()

                        # Batch verification should actively close terminal failed jobs
                        # instead of waiting for the global timeout window.
                        if (self._is_terminal_failed_health(parent_health_norm) or
                                self._is_terminal_failed_health(candidate_health_norm)):
                            terminal_failure = True
                            terminal_reason = (
                                f"terminal_job_health(parent={parent_health_norm or 'unknown'},"
                                f"candidate={candidate_health_norm or 'unknown'})"
                            )

                        if parent_health == 'job_not_found' or candidate_health == 'job_not_found':
                            # checksubmit,  6  job_not_found, 
                            submit_time = verification_jobs.get('submit_time', 0)
                            if submit_time and (current_time - submit_time) > 6 * 3600:
                                job_lost = True
                                lost_reason = f"job_not_found_after_6h (parent: {parent_health}, candidate: {candidate_health})"

                        if terminal_failure:
                            logger.warning(
                                f"verification job terminal failure | task_id: {task_id} | reason: {terminal_reason}"
                            )
                            self.mark_verification_timeout(task_id, reason=terminal_reason)
                            timeout_count += 1
                            continue

                        if job_lost:
                            logger.warning(f"verification job | task_id: {task_id} | reason: {lost_reason}")
                            self.mark_verification_timeout(task_id, reason=lost_reason)
                            timeout_count += 1
                            continue

                        # 
                        waiting_count += 1
                        logger.debug(
                            f"verification jobcompleted | task_id: {task_id} | "
                            f"parent_completed: {parent_completed} | candidate_completed: {candidate_completed}"
                        )
                        continue

                    if verification_passed:
                        # verification success:  errid diff verify
                        introduced_errids = self.calculate_errid_diff(
                            parent_job_id, candidate_job_id
                        )

                        logger.info(
                            f"errid diff completed | task_id: {task_id} | "
                            f"introduced_errids: {len(introduced_errids)}"
                        )

                        # get first_bad_commit
                        first_bad_commit = verification_jobs.get('candidate_commit', '')
                        parent_commit = verification_jobs.get('parent_commit', '')

                        #  git verifycheck()
                        git_verification = None
                        if repo_manager and error_id and self.bisect_instance.is_build_task and introduced_errids:
                            repo_dir = None  #  finally 
                            try:
                                # Acquire repo workspace used by submission jobs.
                                git_url = verification_jobs.get('git_url', '')

                                if git_url and parent_commit and first_bad_commit:
                                    # getrepo
                                    repo_dir, _ = repo_manager.get_repo_dir(
                                        f"verify_{task_id}",
                                        parent_job_id,
                                        git_url
                                    )

                                    #  work_dir  error_id  _verify_errids_with_git
                                    old_work_dir = self.bisect_instance.work_dir
                                    old_error_id = self.bisect_instance.error_id
                                    self.bisect_instance.work_dir = repo_dir
                                    self.bisect_instance.error_id = error_id

                                    try:
                                        #  git verifyerror ID
                                        git_verification = self.bisect_instance._verify_errids_with_git(
                                            parent_commit, first_bad_commit, introduced_errids
                                        )

                                        logger.info(
                                            f"git verifycompleted | task_id: {task_id} | "
                                            f"verified: {git_verification['verified']} | "
                                            f"confidence: {git_verification['confidence']} | "
                                            f"need_human_judgment: {git_verification['need_human_judgment']} | "
                                            f"reason: {git_verification['reason']}"
                                        )
                                    finally:
                                        #  work_dir  error_id
                                        self.bisect_instance.work_dir = old_work_dir
                                        self.bisect_instance.error_id = old_error_id
                            except Exception as e:
                                logger.warning(f"git verifyexception | task_id: {task_id} | error: {str(e)}")
                            finally:
                                # repo
                                if repo_dir and repo_manager:
                                    try:
                                        repo_manager.release_repo_dir(repo_dir)
                                        logger.debug(f" git verifyrepo | task_id: {task_id}")
                                    except Exception as e:
                                        logger.warning(f" Git verification repo cleanup failed | task_id: {task_id} | error: {str(e)}")

                        # verify
                        update_doc = {
                            "updated_at": current_time,
                            "bisect_status": "success",
                            "first_bad_commit": first_bad_commit,
                            "first_bad_id": candidate_job_id,
                            "first_result_root": candidate_result_root,
                            "last_error": "",  # error
                            "j": {
                                "verification_status": "verified",
                                "verified_at": current_time,
                                "introduced_errids": introduced_errids,
                                "parent_job_id": parent_job_id,
                                "candidate_job_id": candidate_job_id,
                                "verification_method": "batch_async_validation",
                                "job_request_count": 2,  # verify2job
                                "is_result_reused": True, # 
                                "job_reused_rate": 1.0,   # 
                                "verification_jobs": {
                                    "status": "completed",
                                    "completed_at": current_time
                                }
                            }
                        }

                        #  git verify()
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
                        logger.info(f"task verification | task_id: {task_id}")

                        #  regression 
                        try:
                            task_query = f"SELECT * FROM bisect WHERE id = {task_id} LIMIT 1"
                            task_results = self.client.sql_select(task_query)

                            if task_results:
                                full_task = task_results[0]
                                if not full_task.get('first_bad_commit'):
                                    full_task['first_bad_commit'] = first_bad_commit

                                write_regression_record(self.client, full_task, first_bad_commit)
                                logger.info(f"Regression  | task_id: {task_id}")

                                # task
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
                            logger.error(f"Regression exception | task_id: {task_id} | error: {str(e)}")

                        completed_count += 1

                    else:
                        # verification failed
                        reason = f"boundary_check_failed_parent_{parent_status}_candidate_{candidate_status}"

                        # Merge verification failure into existing j (preserve commit info)
                        existing_j = {}
                        try:
                            task_row = self.client.sql_select(f"SELECT j FROM bisect WHERE id = {task_id} LIMIT 1")
                            if task_row:
                                existing_j = task_row[0].get('j', {}) or {}
                                if isinstance(existing_j, str):
                                    import json
                                    existing_j = json.loads(existing_j) if existing_j else {}
                        except Exception:
                            pass
                        update_doc = {
                            "bisect_status": "wait",
                            "updated_at": current_time,
                            "j": {**existing_j,
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
                        logger.info(f"taskverification failed | task_id: {task_id} | reason: {reason}")
                        failed_count += 1

                except Exception as e:
                    logger.error(f"checkverification jobfailed | task_id: {task_id} | error: {str(e)}")
                    logger.error(traceback.format_exc())
                    skipped_count += 1

            logger.info(
                f"verification jobcheckcompleted | total: {len(pending_jobs)} | "
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
            logger.error(f"checkverification failed: {str(e)}")
            logger.error(traceback.format_exc())
            return {'checked': 0, 'completed': 0, 'failed': 0, 'timeout': 0, 'waiting': 0, 'skipped': 0}

    def mark_verification_timeout(self, task_id: int, reason: str = "timeout"):
        """verification jobtimeout, reset wait status bisect 

        Args:
            task_id: task ID
            reason: timeoutreason(default 'timeout',  'job_not_found_after_6h' )
        """
        try:
            current_time = int(time.time())

            # querytimeout
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
                logger.warning(f"querytimeoutfailed | task_id: {task_id} | error: {str(e)}")

            new_timeout_count = current_timeout_count + 1

            # Merge timeout metadata into existing j (preserve commit info)
            existing_j = {}
            try:
                task_row = self.client.sql_select(f"SELECT j FROM bisect WHERE id = {task_id} LIMIT 1")
                if task_row:
                    existing_j = task_row[0].get('j', {}) or {}
                    if isinstance(existing_j, str):
                        import json
                        existing_j = json.loads(existing_j) if existing_j else {}
            except Exception:
                pass
            update_doc = {
                "bisect_status": "wait",
                "updated_at": current_time,
                "j": {**existing_j,
                    "verification_jobs": {
                        "status": "timeout",
                        "timeout_time": current_time,
                        "timeout_reason": reason
                    },
                    "verification_status": "timeout",
                    "verification_timeout_count": new_timeout_count,
                    "last_timeout_reason": reason
                }
            }

            self.client.update("bisect", task_id, update_doc)
            logger.info(f"verification jobtimeout, reset wait | task_id: {task_id} | reason: {reason} | timeout_count: {new_timeout_count}")

        except Exception as e:
            logger.error(f"verifytimeoutfailed | task_id: {task_id} | error: {str(e)}")
 
def create_success_task_validator(config: Dict) -> SuccessTaskValidator:
    """createsuccess taskverification serviceinstance"""
    client = ManticoreClient(
        host=config.get('manticore_host', 'localhost'),
        port=int(config.get('manticore_http_port', '9308'))
    )
    return SuccessTaskValidator(client, config)


if __name__ == '__main__':
    """testverification service"""
    # config
    config = {
        'manticore_host': os.environ.get('MANTICORE_HOST', 'localhost'),
        'manticore_http_port': os.environ.get('MANTICORE_HTTP_PORT', '9308'),
        'validation_batch_size': 5,
        'validation_interval': 3600,
        'verification_timeout': 3600,
        'parallel_verification_jobs': 2
    }

    # createverification service
    validator = create_success_task_validator(config)

    # run onceverify
    stats = validator.run_validation_cycle()

    logger.info(f"verifycompleted | stats: {stats}")
