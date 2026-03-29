#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
HEAD regression validator for previously verified bisect tasks.

The validator periodically retests known introduced error IDs on latest HEAD
and updates per-taskTrigger HEAD check notifications status.
"""

import os
import sys
import time
import json
import subprocess
import traceback
import urllib.request
import urllib.error
from typing import Dict, Any, Optional, List, Tuple

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger

sys.path.append((os.environ['LKP_SRC']) + '/sbin/bisect/')
from lkp_bisect.db.manticore import ManticoreClient
from lkp_bisect.core.git_bisect import GitBisect

# Shared runtime imports
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/core')
from verification_consumer import VerificationConsumer
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from repo_manager import SharedRepoManager
from bisect_utils import extract_repo_name_from_url


class HeadValidator(VerificationConsumer):
    """Validate whether known errids still reproduce on latest HEAD."""

    def __init__(self, client: ManticoreClient, config: Dict):
        """Initialize the HEAD validator."""
        super().__init__(client, config)

        # Runtime settings
        self.check_batch_size = config.get('head_check_batch_size', 10)
        self.check_interval = config.get('head_check_interval', 86400)  # default
        self.notification_webhook = config.get('notification_webhook_url', '')
        self.notification_email = config.get('notification_email', '')

        # initialize GitBisect instance
        self.bisect_instance = GitBisect(logger)

        logger.info(
            f"HeadValidator initialized | "
            f"batch_size: {self.check_batch_size} | "
            f"interval: {self.check_interval}s"
        )

    def scan_verified_tasks(self, limit: int = None) -> List[Dict]:
        """Scan verified tasks that are eligible for a HEAD re-check."""
        try:
            batch_size = limit or self.check_batch_size

            # query conditions:
            # 1. j.verification_status = 'verified'
            # 2. j.introduced_errids 
            # 3. head_check_completed  false(py_bisect completed HEAD )
            # 4. (head_check_status  OR head_check_at < 24)
            # 5. check: head_check_status != 'checking'(duplicate submit)
            # 6. failed status: head_check_status != 'failed'
            # 7. regressed_errids (skip already-completed checks)
            current_time = int(time.time())
            check_threshold = current_time - self.check_interval

            sql_query = f"""
                SELECT * FROM bisect
                WHERE j.verification_status = 'verified'
                AND j.introduced_errids IS NOT NULL
                AND (j.head_check_completed IS NULL OR j.head_check_completed = 0)
                AND (j.head_check_status IS NULL OR (
                    j.head_check_status != 'failed'
                    AND j.head_check_status != 'regressed'
                    AND j.head_check_status != 'fixed'
                ))
                AND (j.regressed_errids IS NULL OR j.regressed_errids = '')
                ORDER BY updated_at ASC
                LIMIT {batch_size}
            """

            logger.info(f"scan verification tasks (excluding py_bisect-completedTrigger HEAD check notificationss) | batch_size: {batch_size}")
            results = self.client.sql_select(sql_query)

            if results:
                logger.info(f" {len(results)} tasks to check")
            else:
                logger.info("tasks to check")

            return results or []

        except Exception as e:
            logger.error(f"scan verification tasks failed: {str(e)}")
            logger.error(traceback.format_exc())
            return []

    def get_head_commit(self, repo_dir: str) -> Optional[str]:
        """
        get repo HEAD commit

        Args:
            repo_dir: repo

        Returns:
            HEAD commit hash
        """
        try:
            result = subprocess.run(
                ['git', '-C', repo_dir, 'rev-parse', 'HEAD'],
                capture_output=True,
                text=True,
                check=True,
                timeout=60
            )

            head_commit = result.stdout.strip()
            logger.info(f"get HEAD commit success | commit: {head_commit[:8]}")
            return head_commit

        except subprocess.CalledProcessError as e:
            logger.error(f"get HEAD commit failed | error: {e.stderr}")
            return None
        except subprocess.TimeoutExpired:
            logger.error("get HEAD commit timeout")
            return None
        except Exception as e:
            logger.error(f"get HEAD commit exception: {str(e)}")
            return None

    def get_parent_commit(self, repo_dir: str, commit: str) -> Optional[str]:
        """
        get commit  parent commit (commit^)

        Args:
            repo_dir: repo
            commit: commit hash

        Returns:
            Parent commit hash
        """
        try:
            result = subprocess.run(
                ['git', '-C', repo_dir, 'rev-parse', f'{commit}^'],
                capture_output=True,
                text=True,
                check=True,
                timeout=60
            )

            parent_commit = result.stdout.strip()
            logger.info(f"get parent commit success | commit: {commit[:8]} | parent: {parent_commit[:8]}")
            return parent_commit

        except subprocess.CalledProcessError as e:
            logger.error(f"get parent commit failed | commit: {commit[:8]} | error: {e.stderr}")
            return None
        except subprocess.TimeoutExpired:
            logger.error(f"get parent commit timeout | commit: {commit[:8]}")
            return None
        except Exception as e:
            logger.error(f"get parent commit exception | commit: {commit[:8]} | error: {str(e)}")
            return None

    def submit_head_test(self, task: Dict, head_commit: str) -> Optional[Tuple[str, str]]:
        """
        Submit a HEAD commit test job.

        Args:
            task: bisect task
            head_commit: HEAD commit hash

        Returns:
            (job_id, result_root) or None
        """
        try:
            logger.info(f"submit HEAD test | task_id: {task['id']} | head: {head_commit[:8]}")

            # Submit job through GitBisect.
            # Build base job config.
            bad_job_id = task.get('bad_job_id')
            if not bad_job_id:
                logger.error(f"Missing bad_job_id | task_id: {task['id']}")
                return None

            job_config = self.bisect_instance.init_job_content(bad_job_id)

            #  commit  HEAD
            if 'ss' in job_config and 'linux' in job_config['ss']:
                job_config['ss']['linux']['commit'] = head_commit
            elif 'program' in job_config and 'makepkg' in job_config['program']:
                job_config['program']['makepkg']['commit'] = head_commit
            else:
                logger.error(f"Unsupported job config structure | task_id: {task['id']}")
                return None

            # Submit job.
            job_id, result_root, *_ = self.bisect_instance.submit_job(job_config)
            logger.info(f"HEAD test submitted | job_id: {job_id} | task_id: {task['id']}")

            return (job_id, result_root)

        except Exception as e:
            logger.error(f"submit HEAD test failed: {str(e)} | task_id: {task['id']}")
            logger.error(traceback.format_exc())
            return None

    def check_head_regression(self, task: Dict) -> Dict:
        """
        Check HEAD regression status (with optional parent verification).

        Args:
            task: bisect task

        Returns:
            checkdict
        """
        try:
            task_id = task['id']
            git_url = task.get('git_url')

            logger.info(f"check HEAD Regression detected | task_id: {task_id}")

            if not git_url:
                error_msg = "missing_git_url"
                logger.error(f"{error_msg} | task_id: {task_id}")
                return {'status': 'failed', 'error': error_msg}

            # get error_id( errid )
            original_error_id = task.get('error_id')
            if not original_error_id:
                error_msg = "missing_original_error_id"
                logger.error(f"{error_msg} | task_id: {task_id}")
                return {'status': 'failed', 'error': error_msg}

            # getTrigger HEAD check notifications status(status)
            previous_head_status = None
            j_field = task.get('j', {})
            if isinstance(j_field, str):
                try:
                    j_field = json.loads(j_field) if j_field else {}
                except json.JSONDecodeError:
                    j_field = {}
            previous_head_status = j_field.get('head_check_status')

            if previous_head_status:
                logger.info(f"Previous HEAD status | task_id: {task_id} | status: {previous_head_status}")
            else:
                logger.info(f"FirstTrigger HEAD check notifications | task_id: {task_id}")

            logger.info(f"Target error_id | task_id: {task_id} | error_id: {original_error_id}")

            # Acquire shared repository workspace.
            repo_dir, job_dir = self._get_repo_dir(task_id, task['bad_job_id'], git_url)

            try:
                # get HEAD commit
                head_commit = self.get_head_commit(repo_dir)
                if not head_commit:
                    error_msg = "failed to get head commit"
                    logger.error(f"{error_msg} | task_id: {task_id}")
                    return {'status': 'failed', 'error': error_msg}

                # submit HEAD test
                head_result = self.submit_head_test(task, head_commit)
                if not head_result:
                    error_msg = "failed to submit head test"
                    logger.error(f"{error_msg} | task_id: {task_id}")
                    return {'status': 'failed', 'error': error_msg}

                head_job_id, head_result_root = head_result

                # Poll job stats and evaluate target error_id.
                job_stats, job_health = self.bisect_instance._poll_job_stats(head_job_id, head_result_root)

                #  py_bisect logcheck errid
                # _check_error_id  (status, certainty, reason) 
                error_status, _, _ = self.bisect_instance._check_error_id(job_stats, original_error_id, job_health, head_result_root)

                # checkregression:  errid 
                regressed = (error_status == 'bad')
                new_status = 'regressed' if regressed else 'fixed'
                regressed_errids = [original_error_id] if regressed else []

                logger.info(f"HEAD job completed | log |  errid status: {new_status} | job_id: {head_job_id}")

                # Determine whether status changed from previous run.
                status_changed = (previous_head_status is not None and previous_head_status != new_status)

                if status_changed:
                    logger.warning(
                        f"HEAD status | task_id: {task_id} | "
                        f"{previous_head_status} -> {new_status} | requires_verification"
                    )

                    # Determine whether status changed from previous run.verify: submit HEAD^ (parent) testverify
                    verification_needed = True
                else:
                    logger.info(
                        f"HEAD status check | task_id: {task_id} | "
                        f"status: {new_status} | no_parent_verification_needed"
                    )
                    verification_needed = False

                # Determine whether status changed from previous run. verification with optional parent check
                verified = False
                final_status = new_status  # default outcome

                if verification_needed:
                    # verify: test HEAD^ (parent commit)
                    parent_commit = self.get_parent_commit(repo_dir, head_commit)
                    if parent_commit:
                        logger.info(f"startverify | HEAD: {head_commit[:8]} | parent: {parent_commit[:8]} | task_id: {task_id}")

                        # submit parent commit test
                        parent_result = self.submit_head_test(task, parent_commit)
                        if parent_result:
                            parent_job_id, parent_result_root = parent_result

                            # Poll parent test completion.
                            parent_job_stats, parent_job_health = self.bisect_instance._poll_job_stats(parent_job_id, parent_result_root)
                            # _check_error_id  (status, certainty, reason) 
                            parent_error_status, _, _ = self.bisect_instance._check_error_id(parent_job_stats, original_error_id, parent_job_health, parent_result_root)

                            parent_status = 'bad' if parent_error_status == 'bad' else 'good'

                            logger.info(
                                f"Verification completed | head_status: {new_status} | parent_status: {parent_status} | "
                                f"task_id: {task_id} | parent_job: {parent_job_id}"
                            )

                            # Evaluate verification matrix.
                            if new_status == 'regressed' and parent_status == 'good':
                                # regressed + parent good = regression
                                verified = True
                                final_status = 'regressed'
                                logger.warning(f"verification result: regressed | task_id: {task_id}")
                                # 
                                self.trigger_notification(task, 'regressed', regressed_errids)

                            elif new_status == 'fixed' and parent_status == 'bad':
                                # fixed + parent bad = fixed(parent, )
                                verified = True
                                final_status = 'fixed'
                                logger.info(f"verification result: fixed | task_id: {task_id}")

                            elif new_status == 'fixed' and parent_status == 'good':
                                # fixed + parent good = fixed()
                                verified = True
                                final_status = 'fixed'
                                logger.info(f"verification result: fixed (stable) | task_id: {task_id}")

                            elif new_status == 'regressed' and parent_status == 'bad':
                                # regressed + parent bad = conditions,  flaky test
                                verified = False
                                final_status = 'unverifiable'
                                logger.warning(
                                    f"verification failed: HEAD=bad, parent=bad | task_id: {task_id} | "
                                    f"possible flaky behavior; mark as unverifiable"
                                )

                            else:
                                # 
                                verified = False
                                final_status = 'unverifiable'
                                logger.warning(f"Unexpected verification combination | task_id: {task_id}")

                        else:
                            logger.error(f"Submit parent commit test failed | task_id: {task_id}")
                            verified = False
                            final_status = new_status  # verification unavailable, keep current status
                    else:
                        logger.error(f"get parent commit failed | task_id: {task_id}")
                        verified = False
                        final_status = new_status  # verification unavailable, keep current status
                else:
                    # Determine whether status changed from previous run. check and verification
                    verified = True  # 
                    final_status = new_status

                # 
                self.update_head_check_status(
                    task_id, final_status, head_commit, head_job_id, regressed_errids,
                    verified=verified, status_changed=status_changed
                )

                # Generate/update report when needed:
                # 1. check (previous_head_status is None)
                # 2. statusverify (status_changed and verified)
                should_generate_report = (previous_head_status is None) or (status_changed and verified)

                if should_generate_report:
                    #  bisect success(Trigger HEAD check notifications )
                    try:
                        # Query updated task for report generation.
                        updated_tasks = self.client.sql_select(f"SELECT * FROM bisect WHERE id = {task_id}")
                        if updated_tasks:
                            updated_task = updated_tasks[0]

                            # get job 
                            bad_job_id = task.get('bad_job_id')
                            job_info = None
                            if bad_job_id:
                                try:
                                    job_query = f"SELECT * FROM jobs WHERE id = {int(bad_job_id)} LIMIT 1"
                                    job_results = self.client.sql_select(job_query)
                                    if job_results and len(job_results) > 0:
                                        job_info = job_results[0]
                                except Exception as e:
                                    logger.warning(f"get job failed | job_id: {bad_job_id} | error: {str(e)}")

                            # Read introduced_errids from existing j field.
                            j_field = updated_task.get('j', {})
                            if isinstance(j_field, str):
                                try:
                                    j_field = json.loads(j_field) if j_field else {}
                                except json.JSONDecodeError:
                                    j_field = {}
                            introduced_errids = j_field.get('introduced_errids', []) or []

                            # (file, )
                            report_path = self.notification_writer.write_bisect_success_report(
                                updated_task,
                                job_info=job_info,
                                introduced_errids=introduced_errids
                            )
                            if report_path:
                                logger.info(f"Bisect success report updated | task_id: {task_id} | HEAD: {final_status} | verified: {verified} | path: {report_path}")
                            else:
                                logger.warning(f"Bisect success report generation failed | task_id: {task_id}")
                        else:
                            logger.warning(f"get task failed | task_id: {task_id}")
                    except Exception as e:
                        logger.error(f"Bisect success report exception | task_id: {task_id} | error: {str(e)}")
                        logger.error(traceback.format_exc())
                else:
                    logger.info(f"Status unchanged, skip report generation | task_id: {task_id} | status: {final_status}")

                return {
                    'status': 'success',
                    'task_id': task_id,
                    'head_check_status': final_status,
                    'head_commit': head_commit,
                    'head_job_id': head_job_id,
                    'regressed_errids': regressed_errids,
                    'verified': verified,
                    'status_changed': status_changed
                }

            finally:
                # Release workspace back to shared pool.
                self._release_repo_to_pool(repo_dir, job_dir)

        except Exception as e:
            error_msg = f"check_head_regression_exception: {str(e)}"
            logger.error(f"{error_msg} | task_id: {task.get('id', 'unknown')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg}

    def update_head_check_status(self, task_id: int, status: str, head_commit: str,
                                 head_job_id: str, regressed_errids: List[str],
                                 verified: bool = True, status_changed: bool = False):
        """
        Update HEAD check status fields for a task.

        Args:
            task_id: task ID
            status: status('regressed', 'fixed', 'unverifiable')
            head_commit: HEAD commit hash
            head_job_id: HEAD test job ID
            regressed_errids: regressed errid list
            verified: verification flag
            status_changed: whether status changed in this cycle
        """
        try:
            current_time = int(time.time())

            # Read existing j field to preserve unrelated metadata.
            existing_j = {}
            try:
                task = self.client.sql_select_one(f"SELECT j FROM bisect WHERE id = {task_id}")
                if task and 'j' in task:
                    j_field = task['j']
                    if isinstance(j_field, dict):
                        existing_j = j_field
            except Exception as e:
                logger.warning(f"Failed to parse existing j field | task_id: {task_id} | error: {str(e)}")

            # Merge checking-state fields into j.
            updated_j = {
                **existing_j,  # ( verification_status, introduced_errids )
                "head_check_status": status,
                "head_check_at": current_time,
                "head_check_commit": head_commit,
                "head_check_job_id": head_job_id,
                "head_check_source": "head_validator",
                "head_check_verified": verified,
                "head_check_status_changed": status_changed,
                "regressed_errids": regressed_errids if status == 'regressed' else []
            }

            update_doc = {
                "updated_at": current_time,
                "j": updated_j
            }

            update_result = self.client.update("bisect", task_id, update_doc)

            if update_result:
                logger.info(f"HEAD check status updated | task_id: {task_id} | status: {status}")
            else:
                logger.error(f"HEAD check status update failed | task_id: {task_id}")

        except Exception as e:
            logger.error(f"Trigger HEAD check notifications status update failed: {str(e)} | task_id: {task_id}")
            logger.error(traceback.format_exc())

    def trigger_notification(self, task: Dict, status: str, regressed_errids: List[str]):
        """
        Trigger HEAD check notifications

        Args:
            task: task
            status: status ('regressed' or 'fixed')
            regressed_errids: regressed errid list
        """
        try:
            task_id = task['id']
            first_bad_commit = task.get('first_bad_commit', 'N/A')
            git_url = task.get('git_url', 'N/A')

            if status == 'regressed':
                # Confirmed regression
                message = (
                    f"[HEAD regression]\n"
                    f"task ID: {task_id}\n"
                    f"First Bad Commit: {first_bad_commit}\n"
                    f"regression Errids: {len(regressed_errids)}\n"
                    f"Sample: {regressed_errids[:3]}\n"
                    f"Git URL: {git_url}"
                )

                logger.warning("=" * 60)
                logger.warning(message)
                logger.warning("=" * 60)

                # Write file-based regression notification.
                self.notification_writer.write_head_regression_alert(
                    task=task,  # [OK]  task 
                    regressed_errids=regressed_errids
                )
                logger.info(f"HEAD Regression detected | task_id: {task_id}")

            elif status == 'fixed':
                # Fixed notification
                j_data = task.get('j', {})
                introduced_errids = j_data.get('introduced_errids', [])

                message = (
                    f"[HEAD fixed][OK]\n"
                    f"task ID: {task_id}\n"
                    f"First Bad Commit: {first_bad_commit}\n"
                    f" HEAD fixed!\n"
                    f" Errids: {len(introduced_errids)}\n"
                    f"Git URL: {git_url}"
                )

                logger.info("=" * 60)
                logger.info(message)
                logger.info("=" * 60)

                # fixed
                self.notification_writer.write_head_fixed_report(
                    task=task,
                    introduced_errids=introduced_errids
                )
                logger.info(f"HEAD fixed | task_id: {task_id}")

            # Optional webhook/email integration.
            if self.notification_webhook:
                webhook_payload = {
                    "event": "head_regression" if status == "regressed" else "head_fixed",
                    "task_id": task_id,
                    "status": status,
                    "first_bad_commit": first_bad_commit,
                    "git_url": git_url,
                    "regressed_errids": regressed_errids if status == "regressed" else [],
                    "introduced_errids": introduced_errids if status == "fixed" else [],
                    "timestamp": int(time.time()),
                }
                self._send_webhook_notification(webhook_payload)

            if self.notification_email:
                logger.info(f"TODO: send email notification to {self.notification_email}")

        except Exception as e:
            logger.error(f"Trigger notification failed: {str(e)}")
            logger.error(traceback.format_exc())

    def _send_webhook_notification(self, payload: Dict[str, Any], timeout: int = 10) -> bool:
        """Send notification payload to webhook endpoint."""
        webhook_url = str(self.notification_webhook or '').strip()
        if not webhook_url:
            return False

        data = json.dumps(payload, ensure_ascii=False).encode('utf-8')
        request = urllib.request.Request(
            webhook_url,
            data=data,
            method='POST',
            headers={
                'Content-Type': 'application/json',
                'User-Agent': 'bisect-head-validator/1.0',
            }
        )

        try:
            with urllib.request.urlopen(request, timeout=timeout) as resp:
                status_code = int(getattr(resp, 'status', 0) or resp.getcode())
                if 200 <= status_code < 300:
                    logger.info(
                        f"Webhook notification sent | task_id: {payload.get('task_id')} | "
                        f"event: {payload.get('event')} | status: {status_code}"
                    )
                    return True
                logger.warning(
                    f"Webhook returned non-2xx | task_id: {payload.get('task_id')} | "
                    f"event: {payload.get('event')} | status: {status_code}"
                )
                return False
        except urllib.error.HTTPError as e:
            logger.warning(
                f"Webhook HTTP error | task_id: {payload.get('task_id')} | "
                f"event: {payload.get('event')} | status: {e.code}"
            )
            return False
        except Exception as e:
            logger.warning(
                f"Webhook request failed | task_id: {payload.get('task_id')} | "
                f"event: {payload.get('event')} | error: {str(e)}"
            )
            return False


    def run_head_check_cycle(self) -> Dict[str, int]:
        """
        run onceTrigger HEAD check notifications

        Returns:
            stats dict
        """
        try:
            logger.info("=" * 60)
            logger.info("Start HEAD regression check cycle")
            logger.info("=" * 60)

            # scan verification tasks
            verified_tasks = self.scan_verified_tasks()

            if not verified_tasks:
                logger.info("tasks to check")
                return {
                    'scanned': 0,
                    'regressed': 0,
                    'fixed': 0,
                    'failed': 0
                }

            # Initialize cycle stats.
            stats = {
                'scanned': len(verified_tasks),
                'regressed': 0,
                'fixed': 0,
                'failed': 0
            }

            # tasks to check
            for task in verified_tasks:
                try:
                    result = self.check_head_regression(task)

                    if result.get('status') == 'success':
                        head_status = result.get('head_check_status')
                        if head_status == 'regressed':
                            stats['regressed'] += 1
                        elif head_status == 'fixed':
                            stats['fixed'] += 1
                    else:
                        stats['failed'] += 1

                except Exception as e:
                    logger.error(f"task check exception: {str(e)} | task_id: {task.get('id')}")
                    stats['failed'] += 1

            # stats
            logger.info("=" * 60)
            logger.info(
                f"HEAD check cycle completed | "
                f"scan: {stats['scanned']} | "
                f"regression: {stats['regressed']} | "
                f"fixed: {stats['fixed']} | "
                f"failed: {stats['failed']}"
            )
            logger.info("=" * 60)

            return stats

        except Exception as e:
            logger.error(f"HEAD check cycle exception: {str(e)}")
            logger.error(traceback.format_exc())
            return {
                'scanned': 0,
                'regressed': 0,
                'fixed': 0,
                'failed': 0,
                'error': str(e)
            }


    def _submit_head_test_async(self, task, head_commit):
        """Submit HEAD test asynchronously and persist checking state."""
        try:
            task_id = task['id']

            # submit HEAD test
            head_result = self.submit_head_test(task, head_commit)

            if head_result:
                head_job_id, head_result_root = head_result

                # Read introduced_errids from existing j field.
                j_field = task.get('j', {})
                if isinstance(j_field, str):
                    j_field = json.loads(j_field)

                introduced_errids = j_field.get('introduced_errids', [])

                # Persist job metadata while preserving existing j fields.
                current_time = int(time.time())

                # Parse current j field.
                existing_j = {}
                try:
                    j_field = task.get('j', {})
                    if isinstance(j_field, str):
                        j_field = json.loads(j_field)
                    existing_j = j_field if isinstance(j_field, dict) else {}
                except Exception as e:
                    logger.warning(f"Failed to parse existing j field | task_id: {task_id} | error: {str(e)}")

                # Merge checking-state fields into j.
                updated_j = {
                    **existing_j,  # ( introduced_errids)
                    "head_check_status": "checking",
                    "head_check_job_id": head_job_id,
                    "head_check_result_root": head_result_root,
                    "head_check_commit": head_commit,
                    "head_check_source": "head_validator",
                    "head_check_submitted_at": current_time
                    # Use introduced_errids directly as target set.
                }

                update_doc = {
                    "updated_at": current_time,
                    "j": updated_j
                }
                self.client.update("bisect", task_id, update_doc)

                return {
                    'submitted': True,
                    'head_job_id': head_job_id
                }
            else:
                return {'submitted': False, 'error': 'failed to submit head test'}

        except Exception as e:
            logger.error(f"submit HEAD test exception | task_id: {task.get('id')} | error: {str(e)}")
            logger.error(traceback.format_exc())
            return {'submitted': False, 'error': str(e)}

    def _poll_head_test_results(self):
        """Poll running HEAD-test tasks and finalize completed jobs."""
        try:
            # Query tasks currently in checking state.
            # Process older submissions first.
            sql_query = """
                SELECT id, error_id, j
                FROM bisect
                WHERE j.head_check_status = 'checking'
                ORDER BY j.head_check_submitted_at ASC
                LIMIT 200
            """
            checking_tasks = self.client.sql_select(sql_query)

            if not checking_tasks:
                return

            logger.info(f"Polling HEAD-test tasks | count: {len(checking_tasks)}")

            completed_count = 0
            regressed_count = 0
            fixed_count = 0

            for task in checking_tasks:
                try:
                    task_id = task['id']
                    j_field = task.get('j', {})
                    if isinstance(j_field, str):
                        j_field = json.loads(j_field)

                    head_job_id = j_field.get('head_check_job_id')
                    head_result_root = j_field.get('head_check_result_root')
                    head_commit = j_field.get('head_check_commit')
                    target_errids = j_field.get('introduced_errids', [])  #  introduced_errids
                    submitted_at = j_field.get('head_check_submitted_at', 0)

                    if not head_job_id or not target_errids:
                        logger.warning(
                            f"HEAD-test task missing required data | task_id: {task_id} | "
                            f"head_job_id: {head_job_id} | introduced_errids: {len(target_errids) if target_errids else 0}"
                        )
                        continue

                    # Check whether the HEAD test job has completed.
                    try:
                        head_stats, head_health = self.bisect_instance._poll_job_stats(head_job_id, head_result_root)

                        # Job has completed.
                        if not (isinstance(head_stats, dict) and head_stats):
                            logger.debug(f"HEAD test job not completed yet | task_id: {task_id} | job_id: {head_job_id}")
                            continue

                    except Exception as e:
                        logger.error(f"check HEAD test job status failed | task_id: {task_id} | job_id: {head_job_id} | error: {str(e)}")
                        continue

                    # Job completed; now finalize regression status.
                    logger.info(f"HEAD test completed | task_id: {task_id} | start regression analysis")
                    # Confirmed regressionstatus
                    status = self._finalize_head_check(task, head_job_id, head_commit, target_errids)

                    completed_count += 1
                    if status == 'regressed':
                        regressed_count += 1
                    elif status == 'fixed':
                        fixed_count += 1

                except Exception as e:
                    logger.error(f"HEAD test exception | task_id: {task.get('id')} | error: {str(e)}")

            if completed_count > 0:
                logger.info(
                    f"completedTrigger HEAD check notifications: {completed_count} task | "
                    f"regression: {regressed_count} | fixed: {fixed_count}"
                )

        except Exception as e:
            logger.error(f"HEAD test exception: {str(e)}")
            logger.error(traceback.format_exc())

    def _finalize_head_check(self, task, head_job_id, head_commit, target_errids):
        """completedTrigger HEAD check notifications: regressionstatus"""
        try:
            task_id = task['id']

            # Read errids from HEAD job has no stats.
            job_stats, job_health = self.bisect_instance._poll_job_stats(head_job_id)

            if not job_stats:
                logger.warning(f"HEAD job has no stats | job_id: {head_job_id}")
                head_errids = []
            else:
                head_errids = list(job_stats.keys())

            logger.info(f"HEAD job completed | errids: {len(head_errids)} | job_id: {head_job_id}")

            # Check regression by intersecting target_errids with head_errids.
            regressed_errids = [e for e in target_errids if e in head_errids]

            if regressed_errids:
                # Confirmed regression
                status = 'regressed'
                logger.warning(
                    f"Regression detected | task_id: {task_id} | "
                    f"regressed: {len(regressed_errids)}/{len(target_errids)}"
                )
                logger.warning(f"Regressed errids: {regressed_errids[:3]}...")

                # 
                self.trigger_notification(task, 'regressed', regressed_errids)
            else:
                # fixed
                status = 'fixed'
                logger.info(f"Fixed on HEAD | task_id: {task_id} | no known errids on HEAD")

                # Fixed notification
                self.trigger_notification(task, 'fixed', [])

            # Persist final HEAD-check fields in j.
            current_time = int(time.time())

            # Parse current j field.
            existing_j = {}
            try:
                j_field = task.get('j', {})
                if isinstance(j_field, str):
                    j_field = json.loads(j_field)
                existing_j = j_field if isinstance(j_field, dict) else {}
            except Exception as e:
                logger.warning(f"Failed to parse existing j field | task_id: {task_id} | error: {str(e)}")

            # Trigger HEAD check notificationscompleted J 
            updated_j = {
                **existing_j,  # ( verification )
                "head_check_status": status,
                "head_check_at": current_time,
                "head_check_commit": head_commit,
                "head_check_job_id": head_job_id,
                "head_check_source": "head_validator",
                "regressed_errids": regressed_errids if status == 'regressed' else [],
                "head_check_completed_at": current_time
            }

            update_doc = {
                "updated_at": current_time,
                "j": updated_j
            }

            # check
            update_result = self.client.update("bisect", task_id, update_doc)

            if not update_result:
                logger.error(
                    f"HEAD check database update failed | task_id: {task_id} | status: {status} | "
                    f"update_doc: {update_doc}"
                )
                return 'failed'

            logger.info(f"HEAD check cycle completed | task_id: {task_id} | status: {status}")
            return status

        except Exception as e:
            logger.error(f"Finalize HEAD check exception | task_id: {task.get('id')} | error: {str(e)}")
            logger.error(traceback.format_exc())
            self._mark_head_check_failed(task, f"HEAD check cycle exception: {str(e)}")
            return 'failed'

    def _mark_head_check_failed(self, task: dict, reason: str):
        """Mark HEAD check as failed

        Args:
            task: task dict
            reason: failure reason
        """
        try:
            task_id = task.get('id') if isinstance(task, dict) else task
            current_time = int(time.time())

            # Parse current j field.
            existing_j = {}
            try:
                j_field = task.get('j', {}) if isinstance(task, dict) else {}
                if isinstance(j_field, str):
                    j_field = json.loads(j_field)
                existing_j = j_field if isinstance(j_field, dict) else {}
            except Exception as e:
                logger.warning(f"Failed to parse existing j field | task_id: {task_id} | error: {str(e)}")

            # Merge failure-state fields into j.
            updated_j = {
                **existing_j,  # 
                "head_check_status": "failed",
                "head_check_source": "head_validator",
                "head_check_failure_reason": reason,
                "head_check_failed_at": current_time
            }

            update_doc = {
                "updated_at": current_time,
                "j": updated_j
            }
            self.client.update("bisect", task_id, update_doc)
            logger.info(f"HEAD check database update failed | task_id: {task_id} | reason: {reason}")

            # Write timeout alert for file-based notifications.
            if "timeout" in reason:
                try:
                    self.notification_writer.write_timeout_alert(
                        task_id=task_id,
                        error_id=task.get('error_id', 'unknown'),
                        timeout_type='head_check',
                        reason=reason
                    )
                    logger.info(f"HEAD check timeout alert written | task_id: {task_id}")
                except Exception as e:
                    logger.error(f"HEAD check timeout notification exception | task_id: {task_id} | error: {str(e)}")

        except Exception as e:
            task_id = task.get('id') if isinstance(task, dict) else task
            logger.error(f"Trigger HEAD check notifications failed exception | task_id: {task_id} | error: {str(e)}")

def create_head_validator(config: Dict) -> HeadValidator:
    """Create HEAD validator instance"""
    client = ManticoreClient(
        host=config.get('manticore_host', 'localhost'),
        port=int(config.get('manticore_http_port', '9308'))
    )
    return HeadValidator(client, config)


if __name__ == '__main__':
    """Manual test entry for HEAD validator."""
    # config
    config = {
        'manticore_host': os.environ.get('MANTICORE_HOST', 'localhost'),
        'manticore_http_port': os.environ.get('MANTICORE_HTTP_PORT', '9308'),
        'head_check_batch_size': 5,
        'head_check_interval': 86400,  # 
        'notification_webhook_url': '',
        'notification_email': ''
    }

    # Create validator instance.
    validator = create_head_validator(config)

    # run oncecheck
    stats = validator.run_head_check_cycle()

    logger.info(f"HEAD check cycle completed | stats: {stats}")
