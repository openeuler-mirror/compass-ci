#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
VerificationConsumer for boundary verification and result reuse.

This module validates candidate commits for similar tasks with lightweight
job checks, so we can reuse verified bisect results and avoid full reruns.
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

sys.path.append((os.environ['LKP_SRC']) + '/sbin/bisect/')
from lkp_bisect.db.manticore import ManticoreClient
from lkp_bisect.core.git_bisect import GitBisect


class VerificationConsumer:
    """Process tasks in `pending_verification` with boundary checks."""

    def __init__(self, client: ManticoreClient, config: Dict):
        self.client = client
        self.config = config
        # Verification uses a dedicated repo manager.
        self.repo_manager = SharedRepoManager()
        self.running = True

        # Verification settings
        self.verification_timeout = config.get('verification_timeout', 3600)  # 1 hour
        self.parallel_jobs = config.get('parallel_verification_jobs', 2)
        self.max_retry_count = config.get('verification_max_retry', 3)

        # Notification integration
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
            logger.info(f"start verification task | id: {task_id}")

            # Read task metadata (including introduced_errids)
            task_metadata = self._get_task_metadata(task)
            if not task_metadata:
                error_msg = "failed to get task metadata"
                logger.error(f"{error_msg} | ID: {task_id}")
                return {'status': 'failed', 'error': error_msg, 'id': task_id}

            candidate_commit = task_metadata.get('candidate_commit')
            related_task_id = task_metadata.get('related_task_id')
            introduced_errids = task_metadata.get('introduced_errids', [])
            parent_job_id = task_metadata.get('parent_job_id')
            parent_commit = task_metadata.get('parent_commit')

            if not candidate_commit or not related_task_id:
                error_msg = "missing candidate commit or related task id"
                logger.error(f"{error_msg} | ID: {task_id} | metadata: {task_metadata}")
                return {'status': 'failed', 'error': error_msg, 'id': task_id}

            logger.info(f"verification input | candidate_commit: {candidate_commit} | task: {related_task_id}")
            logger.info(f"related task introduced_errids: {len(introduced_errids)} ")
            if introduced_errids and len(introduced_errids) <= 5:
                logger.info(f"  Sample: {introduced_errids[:5]}")

            # Resolve git_url using task -> related task -> jobs fallback chain.
            git_url = task.get('git_url')

            if not git_url:
                # Try related task metadata first.
                git_url = task_metadata.get('related_git_url')
                if git_url:
                    logger.info(f"git_url from related task metadata: {git_url}")

            if not git_url:
                # : get git_url from related task
                logger.info(f"Task missing git_url; query related task | related_task_id: {related_task_id}")
                git_url = self._get_git_url_from_related_task(related_task_id)

            if not git_url:
                # lookup git_url from jobs
                logger.info(f"lookup git_url from jobs | bad_job_id: {task.get('bad_job_id')}")
                git_url = self._get_git_url_from_job(task.get('bad_job_id'))

            if not git_url:
                error_msg = "resolve git repoURL(task,task,jobs)"
                logger.error(f"{error_msg} | ID: {task_id}")
                return {'status': 'failed', 'error': error_msg, 'id': task_id}

            logger.info(f"Resolved git_url: {git_url}")

            # Acquire shared repo workspace.
            repo_dir, job_dir = self._get_repo_dir(task_id, task['bad_job_id'], git_url)

            try:
                # Resolve parent commit for candidate.
                parent_commit = self._get_parent_commit(repo_dir, candidate_commit)
                if not parent_commit:
                    error_msg = f"failed to get parent commit | commit: {candidate_commit}"
                    logger.error(f"{error_msg} | ID: {task_id}")
                    return {'status': 'failed', 'error': error_msg, 'id': task_id}

                logger.info(f"Parent commit resolved | candidate: {candidate_commit} | parent: {parent_commit}")

                # Submit verification jobs for parent/candidate.
                verification_result = self._submit_parallel_verification_jobs(
                    task, repo_dir, parent_commit, candidate_commit
                )

                if verification_result['status'] == 'success':
                    if verification_result.get('verifiable', False):
                        # verification success, filecheck(, )
                        file_check_result = None
                        try:
                            error_id = task.get('error_id', '')
                            if error_id:
                                # get commit filelist
                                changed_files = self._get_commit_changed_files(repo_dir, candidate_commit)

                                # checkfileerrorlog
                                file_check_result = self._check_files_mentioned_in_error(error_id, changed_files)

                                # filecheck verification_result
                                verification_result['file_check'] = file_check_result

                                if not file_check_result.get('mentioned', False):
                                    logger.warning(
                                        f"File-check warning | task_id: {task_id} | "
                                        f"commit fileerrorlog, "
                                    )
                            else:
                                logger.debug(f"skipfilecheck: error_id  | task_id: {task_id}")

                        except Exception as e:
                            logger.error(f"File-check failed: {str(e)} | task_id: {task_id}")
                            logger.error(traceback.format_exc())
                            # File-check failedverify, 

                        # verification success, ( task_metadata get introduced_errids)
                        return self._handle_verification_success(task, verification_result, task_metadata)
                    else:
                        # verification failed, conditions, bisect
                        return self._handle_verification_failure(task, verification_result)
                else:
                    # verification failed, bisect
                    return self._handle_verification_failure(task, verification_result)

            finally:
                # repo(delete)
                self._release_repo_to_pool(repo_dir, job_dir)

        except Exception as e:
            error_msg = f"verification task exception: {str(e)}"
            logger.error(f"{error_msg} | ID: {task.get('id', 'unknown')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg, 'id': task.get('id', 'unknown')}

    def _get_task_metadata(self, task: Dict) -> Optional[Dict]:
        """taskjget"""
        try:
            j_field = task.get('j', {})
            if isinstance(j_field, str):
                import json
                j_field = json.loads(j_field)

            related_task_id = j_field.get('related_task_id')

            if not related_task_id:
                logger.error(f"Task missing related_task_id; cannot verify | task_id: {task['id']}")
                return None

            # taskget( introduced_errids)
            related_task = self._get_related_task(related_task_id)
            if not related_task:
                logger.error(f"Failed to get related task | related_task_id: {related_task_id}")
                return None

            candidate_commit = related_task.get('first_bad_commit')

            if not candidate_commit:
                logger.warning(f"Related task missing first_bad_commit; bisect may be incomplete | related_task_id: {related_task_id}")
                return None

            # task j 
            related_j = related_task.get('j', {})
            if isinstance(related_j, str):
                related_j = json.loads(related_j) if related_j else {}

            return {
                'candidate_commit': candidate_commit,
                'related_task_id': related_task_id,
                'error_signature': j_field.get('error_signature', ''),
                'related_git_url': related_task.get('git_url'),
                # : taskget introduced_errids 
                'introduced_errids': related_j.get('introduced_errids', []),
                'parent_job_id': related_j.get('parent_job_id'),
                'parent_commit': related_j.get('parent_commit')
            }

        except Exception as e:
            logger.error(f"Parse task metadata failed: {str(e)} | task.j: {task.get('j')}")
            return None

    def _get_related_task(self, related_task_id: str) -> Optional[Dict]:
        """Get full related-task record from bisect table."""
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
                # Require related task to be successful.
                if task.get('bisect_status') != 'success':
                    logger.warning(f"Related task is not success | related_task_id: {related_task_id} | status: {task.get('bisect_status')}")
                    return None
                return task

            logger.error(f"Related task not found | related_task_id: {related_task_id}")
            return None

        except Exception as e:
            logger.error(f"get task failed: {str(e)} | related_task_id: {related_task_id}")
            return None

    def _get_git_url_from_related_task(self, related_task_id: str) -> Optional[str]:
        """get git_url from related task"""
        try:
            if not related_task_id:
                return None

            # Query related tasks.
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
                    logger.info(f"Got git_url from related task | related_task_id: {related_task_id} | git_url: {git_url}")
                    return git_url

            logger.warning(f"No git_url in related task | related_task_id: {related_task_id}")
            return None

        except Exception as e:
            logger.error(f"get git_url from related task failed: {str(e)} | related_task_id: {related_task_id}")
            return None

    def _get_git_url_from_job(self, bad_job_id: str) -> Optional[str]:
        """lookup git_url from jobs"""
        try:
            if not bad_job_id:
                return None

            # Query jobs index for full_text_kv.
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
                    # git_url
                    git_url = extract_git_url_from_full_text_kv(full_text_kv)
                    if git_url:
                        logger.info(f"jobsgit_url | bad_job_id: {bad_job_id} | git_url: {git_url}")
                        return git_url

            logger.warning(f"jobsgit_url | bad_job_id: {bad_job_id}")
            return None

        except Exception as e:
            logger.error(f"lookup git_url from jobs failed: {str(e)} | bad_job_id: {bad_job_id}")
            return None

    def _get_repo_dir(self, task_id: str, bad_job_id: str, repo_url: str) -> Tuple[str, str]:
        """Return shared repo and job workspace directories."""
        return self.repo_manager.get_repo_dir(task_id, bad_job_id, repo_url)

    def _get_parent_commit(self, repo_dir: str, commit: str) -> Optional[str]:
        """Get parent commit of a given commit."""
        try:
            # gitgetsubmit
            result = subprocess.run(
                ['git', '-C', repo_dir, 'rev-parse', f'{commit}^1'],
                capture_output=True,
                text=True,
                check=True,
                timeout=60  # 60timeout
            )

            parent_commit = result.stdout.strip()
            if not parent_commit:
                logger.warning(f"submit {commit} submit(submit)")
                return None

            logger.debug(f"Got parent commit | commit: {commit} | parent: {parent_commit}")
            return parent_commit

        except subprocess.CalledProcessError as e:
            logger.error(f"Get parent commit failed | commit: {commit} | error: {e.stderr}")
            return None
        except subprocess.TimeoutExpired:
            logger.error(f"Get parent commit timeout | commit: {commit}")
            return None
        except Exception as e:
            logger.error(f"Get parent commit exception | commit: {commit} | error: {str(e)}")
            return None

    def _submit_parallel_verification_jobs(self, task: Dict, repo_dir: str,
                                         parent_commit: str, candidate_commit: str) -> Dict:
        """Submit parent/candidate verification jobs in parallel."""
        try:
            task_id = task['id']
            bad_job_id = task['bad_job_id']
            git_url = task['git_url']

            logger.info(f"startverify | submit: {parent_commit} | : {candidate_commit}")

            # createverification job
            verification_jobs = [
                {
                    'name': f'verification_parent_{task_id}',
                    'commit': parent_commit,
                    'expected_result': 'good',  # submit
                    'task_id': task_id,
                    'type': 'parent'
                },
                {
                    'name': f'verification_candidate_{task_id}',
                    'commit': candidate_commit,
                    'expected_result': 'bad',   # submit
                    'task_id': task_id,
                    'type': 'candidate'
                }
            ]

            # Submit job.
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
                        logger.info(f"verification jobcompleted | type: {job_info['type']} | commit: {job_info['commit']} | result: {result}")
                    except Exception as e:
                        logger.error(f"verification job exception | type: {job_info['type']} | error: {str(e)}")
                        job_results[job_info['type']] = {'status': 'error', 'error': str(e)}

            # verify
            return self._analyze_verification_results(job_results, parent_commit, candidate_commit)

        except Exception as e:
            logger.error(f"verification exception: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def _submit_single_verification_job(self, job_info: Dict, original_task: Dict,
                                      repo_dir: str) -> Dict:
        """Submit one verification job and wait for status."""
        try:
            commit = job_info['commit']
            expected_result = job_info['expected_result']
            job_type = job_info['type']

            logger.info(f"Submit verification job | type: {job_type} | commit: {commit} | expected: {expected_result}")

            # Build and submit job config through GitBisect.
            bisect_instance = GitBisect(logger)

            try:
                # taskbad_job_idjobconfig
                bad_job_id = original_task.get('bad_job_id')
                if not bad_job_id:
                    return {'status': 'error', 'error': 'bad_job_id'}

                # jobconfig
                job_config = bisect_instance.init_job_content(bad_job_id)

                # Replace commit with verification target commit.
                if 'ss' in job_config and 'linux' in job_config['ss']:
                    job_config['ss']['linux']['commit'] = commit
                elif 'program' in job_config and 'makepkg' in job_config['program']:
                    job_config['program']['makepkg']['commit'] = commit
                else:
                    return {'status': 'error', 'error': 'job'}

                # Submit job.
                job_id, result_root, *_ = bisect_instance.submit_job(job_config)
                logger.info(f"job submit succeeded | job_id: {job_id} | type: {job_type} | commit: {commit}")

                # jobcompletedgetstatus
                error_id = original_task.get('error_id', '')
                status = self._wait_for_job_status(bisect_instance, job_id, error_id, job_type)

                # 
                job_result = {
                    'status': 'completed',
                    'job_id': job_id,  #  job_id  errid diff 
                    'test_result': 'passed' if status == 'good' else 'failed',
                    'exit_code': 0 if status == 'good' else 1,
                    'actual_status': status
                }

                logger.info(f"verification jobcompleted | job_id: {job_id} | type: {job_type} | commit: {commit} | status: {status}")
                return job_result

            except Exception as e:
                logger.error(f"job submit or status check failed | type: {job_type} | error: {str(e)}")
                return {'status': 'error', 'error': str(e)}

        except Exception as e:
            logger.error(f"verification job exception | type: {job_type} | error: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def _wait_for_job_status(self, bisect_instance: GitBisect, job_id: str, error_id: str, job_type: str) -> str:
        """jobcompletedcheckstatus"""
        try:
            logger.info(f"jobcompleted | job_id: {job_id} | type: {job_type}")

            # Poll job stats through bisect instance.
            job_stats, job_health = bisect_instance._poll_job_stats(job_id)

            # jobcheckstatus
            if job_type == 'candidate':
                # submit: errid
                has_error = bisect_instance._has_error_id(job_stats, error_id)
                status = 'bad' if has_error else 'good'
                logger.info(f"submitverification input | candidate_commit: {job_id} | has_error: {has_error} | status: {status}")
            else:  # parent
                # submit: not founderrid
                has_error = bisect_instance._has_error_id(job_stats, error_id)
                status = 'good' if not has_error else 'bad'
                logger.info(f"submitverification input | candidate_commit: {job_id} | has_error: {has_error} | status: {status}")

            return status

        except Exception as e:
            logger.error(f"job status exception | job_id: {job_id} | error: {str(e)}")
            return 'skip'

    def _submit_real_job(self, original_task: Dict, commit: str, job_type: str) -> Optional[int]:
        """Submit real verification job to scheduler API."""
        try:
            # getAPIconfig
            sched_host = os.environ.get('SCHED_HOST', 'localhost')
            sched_port = os.environ.get('SCHED_PORT', '3000')
            api_url = f"http://{sched_host}:{sched_port}/scheduler/v1/jobs/submit"

            # verification jobconfig
            job_config = self._build_verification_job_config(original_task, commit, job_type)

            logger.info(f"submitverification job | type: {job_type} | commit: {commit} | API: {api_url}")

            # Submit job.
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
                    logger.info(f"job submit succeeded | job_id: {job_id} | type: {job_type} | commit: {commit}")
                    return int(job_id)
                else:
                    logger.error(f"job submit succeededjob_id | response: {result}")
                    return None
            else:
                logger.error(f"job submit failed | status: {response.status_code} | response: {response.text}")
                return None

        except requests.exceptions.RequestException as e:
            logger.error(f"job submit exception: {str(e)}")
            return None
        except Exception as e:
            logger.error(f"job submit exception: {str(e)}")
            return None

    def _build_verification_job_config(self, original_task: Dict, commit: str, job_type: str) -> Dict:
        """verification jobconfig"""
        # Read error_id and related fields from original task.
        error_id = original_task.get('error_id', '')
        bad_job_id = original_task.get('bad_job_id', '')
        git_url = original_task.get('git_url', '')

        # job
        job_name = f"verification_{job_type}_{original_task['id']}_{commit[:8]}"

        # test
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

        # submitverify, good
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
        """jobcompletedget - """
        try:
            logger.info(f"jobcompleted | job_id: {job_id} | commit: {commit} | type: {job_type}")

            # 
            time.sleep(2)  # jobstatus

            # jobqueryAPIget
            # , 

            import random

            # verify
            scenarios = [
                {'status': 'completed', 'test_result': 'passed', 'exit_code': 0},     # good commit
                {'status': 'completed', 'test_result': 'failed', 'exit_code': 1},     # bad commit
                {'status': 'completed', 'test_result': 'error', 'exit_code': 2},      # test error
                {'status': 'failed', 'error': 'Job execution failed'},                 # job failure
            ]

            # job
            if job_type == 'parent':
                # submit (good)
                result = random.choice([
                    {'status': 'completed', 'test_result': 'passed', 'exit_code': 0},
                    {'status': 'completed', 'test_result': 'failed', 'exit_code': 1},  # 
                    {'status': 'failed', 'error': 'Job execution failed'}
                ])
            else:  # candidate
                # submit (bad)
                result = random.choice([
                    {'status': 'completed', 'test_result': 'failed', 'exit_code': 1},
                    {'status': 'completed', 'test_result': 'passed', 'exit_code': 0},   # 
                    {'status': 'failed', 'error': 'Job execution failed'}
                ])

            logger.info(f"jobcompleted | job_id: {job_id} | result: {result}")
            return result

        except Exception as e:
            logger.error(f"job completion exception | job_id: {job_id} | error: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def _analyze_verification_results(self, job_results: Dict, parent_commit: str, candidate_commit: str) -> Dict:
        """Analyze parent/candidate verification results."""
        try:
            parent_result = job_results.get('parent', {})
            candidate_result = job_results.get('candidate', {})

            logger.info(f"verify | parent: {parent_result} | candidate: {candidate_result}")

            #  job_id( errid diff )
            parent_job_id = parent_result.get('job_id')
            candidate_job_id = candidate_result.get('job_id')

            # Check whether jobs failed.
            if parent_result.get('status') != 'completed' or candidate_result.get('status') != 'completed':
                error_msg = f"verification job failed | parent_status: {parent_result.get('status')} | candidate_status: {candidate_result.get('status')}"
                logger.error(error_msg)
                return {'status': 'failed', 'error': error_msg}

            # Check boundary verification conditions.
            parent_status = parent_result.get('actual_status')
            candidate_status = candidate_result.get('actual_status')

            logger.info(f"verifystatus | parent_status: {parent_status} | candidate_status: {candidate_status}")

            # verification successconditions: 
            # 1) parent status is good (errid absent)
            # 2) candidate status is bad (errid present)
            if parent_status == 'good' and candidate_status == 'bad':
                logger.info("verification success | commit")
                return {
                    'status': 'success',
                    'verifiable': True,
                    'parent_commit': parent_commit,
                    'candidate_commit': candidate_commit,
                    'parent_job_id': parent_job_id,        # saved parent/candidate verification job IDs
                    'candidate_job_id': candidate_job_id,  # saved parent/candidate verification job IDs
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
                # verification failed, conditions
                reason = f"conditions: parent_status={parent_status}, candidate_status={candidate_status}"
                logger.warning(f"verification failed | {reason}")
                return {
                    'status': 'success',
                    'verifiable': False,
                    'parent_commit': parent_commit,
                    'candidate_commit': candidate_commit,
                    'parent_job_id': parent_job_id,        # : verification failed
                    'candidate_job_id': candidate_job_id,  # : verification failed
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
            logger.error(f"verification exception: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def _handle_verification_success(self, task: Dict, verification_result: Dict, task_metadata: Dict) -> Dict:
        """verification success - (related task introduced_errids)"""
        try:
            task_id = task['id']
            candidate_commit = verification_result['candidate_commit']
            parent_commit = verification_result.get('parent_commit')
            parent_job_id = verification_result.get('parent_job_id')
            candidate_job_id = verification_result.get('candidate_job_id')

            logger.info(f"Verification success | task_id: {task_id} | first_bad_commit: {candidate_commit}")
            logger.info(f"verification job | parent_job: {parent_job_id} | candidate_job: {candidate_job_id}")

            # related task introduced_errids
            introduced_errids = task_metadata.get('introduced_errids', [])

            # related task introduced_errids, 
            if not introduced_errids and parent_job_id and candidate_job_id:
                try:
                    logger.warning(f"related task introduced_errids,  | parent: {parent_job_id} | candidate: {candidate_job_id}")
                    introduced_errids = self.calculate_errid_diff(parent_job_id, candidate_job_id)
                    logger.info(f" introduced_errids: {len(introduced_errids)} ")
                    if introduced_errids and len(introduced_errids) <= 5:
                        logger.info(f"  Sample: {introduced_errids[:5]}")
                except Exception as e:
                    logger.error(f" errid diff failed: {str(e)} |  HEAD ")
                    logger.error(traceback.format_exc())
            else:
                logger.info(f"related task introduced_errids: {len(introduced_errids)} ")

            # Mark task success and persist reused commit/job metadata.
            current_time = int(time.time())

            #  j 
            j_field = {
                "verification_status": "verified",  #  'verified'  HeadValidator scan
                "verification_details": verification_result.get('verification_details', {}),
                "result_source": "reused",  # 
                "verification_parent_commit": parent_commit,
                "verification_candidate_commit": candidate_commit,
                "verification_parent_job_id": parent_job_id,
                "verification_candidate_job_id": candidate_job_id,
                "verification_passed": True,
                "result_reused_from": task_metadata.get('related_task_id'),
                "introduced_errids": introduced_errids,  #  introduced_errids
                "introduced_errids_count": len(introduced_errids)
            }

            # filecheck()
            file_check_result = verification_result.get('file_check')
            if file_check_result:
                j_field['file_check_result'] = file_check_result
                logger.info(
                    f"filecheck | task_id: {task_id} | "
                    f"mentioned: {file_check_result.get('mentioned', False)} | "
                    f"ratio: {file_check_result.get('mention_ratio', 0):.1%}"
                )

            # 
            confidence_level = self._calculate_confidence_level(file_check_result)
            j_field['confidence_level'] = confidence_level

            if confidence_level == 'low':
                logger.warning(
                    f" bisect  | task_id: {task_id} | "
                    f"mention_ratio: {file_check_result.get('mention_ratio', 0) if file_check_result else 0:.1%} | "
                    f", "
                )
            elif confidence_level == 'medium':
                logger.info(
                    f" bisect  | task_id: {task_id} | "
                    f"mention_ratio: {file_check_result.get('mention_ratio', 0) if file_check_result else 0:.1%} | "
                    f""
                )

            success_doc = {
                "bisect_status": "success",
                "first_bad_commit": candidate_commit,
                "updated_at": current_time,
                "end_time": current_time,
                "start_time": current_time - 300,  # verify5
                "last_error": "",  # error
                "j": j_field
            }

            # 
            update_result = self.client.update("bisect", task_id, success_doc)
            if update_result:
                logger.info(f"Task status updated | task_id: {task_id} | status: success | source: reused | introduced_errids: {len(introduced_errids)}")

                #  regression (verify)
                try:
                    write_success = write_regression_record(self.client, task, candidate_commit)
                    if write_success:
                        logger.info(f"Regression  | task_id: {task_id} | error_id: {task.get('error_id')}")
                    else:
                        logger.warning(f"Regression failed | task_id: {task_id}")
                except Exception as e:
                    logger.error(f"Regression exception | task_id: {task_id} | error: {str(e)}")

                # : bisect success HEAD validator
                # Reset HEAD-check completion flags to trigger fresh HEAD validation.
                # duplicate,  HEAD verify

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
                error_msg = "failed"
                logger.error(f"{error_msg} | ID: {task_id}")
                return {'status': 'failed', 'error': error_msg, 'id': task_id}

        except Exception as e:
            error_msg = f"verification success exception: {str(e)}"
            logger.error(f"{error_msg} | ID: {task.get('id', 'unknown')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg, 'id': task.get('id', 'unknown')}

    def _handle_verification_failure(self, task: Dict, verification_result: Dict) -> Dict:
        """verification failed - failedreasonverify"""
        try:
            task_id = task['id']
            reason = verification_result.get('reason', 'verification failed')

            # failedreasonconditions(flaky testbisecterror)
            if "conditions" in reason:
                # parent=good, candidate=good, flaky testbisecterror
                # bisect, verify, 
                logger.warning(f"verification failed: boundary conditions not satisfied | ID: {task_id} | verify")

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
                        "unverifiable_reason": "conditions(flaky testbisecterror)"
                    }
                }

                # 
                update_result = self.client.update("bisect", task_id, unverifiable_doc)
                if update_result:
                    logger.info(f"task verification fallback | task_id: {task_id} | ")

                    # file
                    try:
                        # get j  change_point( commit )
                        j_field = task.get('j', {})
                        if isinstance(j_field, str):
                            try:
                                import json
                                j_field = json.loads(j_field) if j_field else {}
                            except json.JSONDecodeError:
                                j_field = {}

                        #  change_point,  first_bad_commit + subject
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
                        logger.info(f"verification taskfile | task_id: {task_id}")
                    except Exception as e:
                        logger.error(f"verification task exception | task_id: {task_id} | error: {str(e)}")

                    return {
                        'status': 'success',
                        'id': task_id,
                        'verification_passed': False,
                        'unverifiable': True
                    }
                else:
                    error_msg = "failed"
                    logger.error(f"{error_msg} | ID: {task_id}")
                    return {'status': 'failed', 'error': error_msg, 'id': task_id}

            else:
                # failedreason(timeout,error), bisect
                logger.info(f"verification failed, bisect | ID: {task_id} | reason: {reason}")

                # Reset task to wait so it can run standard bisect.
                current_time = int(time.time())
                # Merge verification failure into existing j (preserve commit info)
                existing_j = {}
                try:
                    task_row = self.client.sql_select(f"SELECT j FROM bisect WHERE id = {task_id} LIMIT 1")
                    if task_row:
                        existing_j = task_row[0].get('j', {}) or {}
                        if isinstance(existing_j, str):
                            existing_j = json.loads(existing_j) if existing_j else {}
                except Exception:
                    pass
                reset_doc = {
                    "bisect_status": "wait",
                    "updated_at": current_time,
                    "j": {**existing_j,
                        "verification_status": "failed",
                        "verification_failure_reason": reason,
                        "verification_details": verification_result.get('verification_details', {}),
                        "verification_attempted": True,
                        "verification_passed": False,
                        "fallback_to_standard_bisect": True
                    }
                }

                update_result = self.client.update("bisect", task_id, reset_doc)
                if update_result:
                    logger.info(f"Task reset to wait | task_id: {task_id} | fallback: standard_bisect")
                    return {
                        'status': 'success',
                        'id': task_id,
                        'verification_passed': False,
                        'fallback_to_standard_bisect': True
                    }
                else:
                    error_msg = "failed"
                    logger.error(f"{error_msg} | ID: {task_id}")
                    return {'status': 'failed', 'error': error_msg, 'id': task_id}

        except Exception as e:
            error_msg = f"verification failure exception: {str(e)}"
            logger.error(f"{error_msg} | ID: {task.get('id', 'unknown')}")
            logger.error(traceback.format_exc())
            return {'status': 'failed', 'error': error_msg, 'id': task.get('id', 'unknown')}

    def _release_repo_to_pool(self, repo_dir: str, job_dir: str):
        """repo(faileddelete)"""
        try:
            if os.path.exists(repo_dir):
                # 
                self.repo_manager.release_repo_dir(repo_dir)
                logger.info(f"repo: {repo_dir}")
        except Exception as e:
            # failed, delete
            logger.warning(f"repo cleanup failed, delete failed: {str(e)} | path: {repo_dir}")
            self._cleanup_repo_dir(job_dir)

    def _cleanup_repo_dir(self, job_dir: str):
        """repo(failed)"""
        try:
            if os.path.exists(job_dir):
                import shutil
                shutil.rmtree(job_dir, ignore_errors=True)
                logger.debug(f"repocompleted: {job_dir}")
        except Exception as e:
            logger.error(f"repo cleanup failed: {str(e)} | path: {job_dir}")

    def get_all_errids_from_job(self, job_id: str) -> List[str]:
        """
        job errid

        Args:
            job_id: jobID

        Returns:
            errid list
        """
        try:
            if not job_id:
                logger.warning("job_id is empty, cannot extract errids")
                return []

            logger.info(f" errid | job_id: {job_id}")

            # Use GitBisect _poll_job_stats to read job stats.
            bisect_instance = GitBisect(logger)
            job_stats, _ = bisect_instance._poll_job_stats(job_id)

            if not job_stats:
                logger.warning(f"No stats found for job {job_id}")
                return []

            # stats dict,  keys  errids
            errids = list(job_stats.keys())
            logger.info(f"Extracted {len(errids)} errids from job {job_id}")

            #  errid 
            if errids:
                logger.debug(f"Sample errids: {errids[:3]}...")

            return errids

        except Exception as e:
            logger.error(f"Failed to extract errids from job {job_id}: {str(e)}")
            logger.error(traceback.format_exc())
            return []

    def calculate_errid_diff(self, parent_job_id: str, bad_job_id: str) -> List[str]:
        """
         errid : bad_job  errid

        Args:
            parent_job_id: verification parent job ID
            bad_job_id: submit(bad commit)jobID

        Returns:
             errid list( bad_job  parent_job not found errid)
        """
        try:
            logger.info(f" errid diff | parent_job: {parent_job_id} | bad_job: {bad_job_id}")

            # Get errids from both jobs.
            parent_errids = self.get_all_errids_from_job(parent_job_id)
            bad_errids = self.get_all_errids_from_job(bad_job_id)

            # : bad_job  parent_job  errid
            parent_set = set(parent_errids)
            bad_set = set(bad_errids)
            introduced_errids = list(bad_set - parent_set)

            logger.info(
                f"errid diff  | "
                f"parent: {len(parent_errids)} errids | "
                f"bad: {len(bad_errids)} errids | "
                f"introduced: {len(introduced_errids)} errids"
            )

            if introduced_errids:
                # 5, log
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
        get commit filelist

        Args:
            repo_dir: Git repo
            commit: commit hash

        Returns:
            filelist
        """
        try:
            logger.debug(f"get commit file | commit: {commit[:12]}")

            #  git show --name-only getfilelist
            result = subprocess.run(
                ['git', '-C', repo_dir, 'show', '--name-only', '--format=', commit],
                capture_output=True,
                text=True,
                check=True,
                timeout=60
            )

            # 
            files = [f.strip() for f in result.stdout.split('\n') if f.strip()]

            logger.info(f"commit {commit[:12]}  {len(files)} file")
            if files and len(files) <= 10:
                logger.debug(f"  file: {files}")
            elif files:
                logger.debug(f"  file(10): {files[:10]}")

            return files

        except subprocess.CalledProcessError as e:
            logger.error(f"get commit file list failed | commit: {commit[:12]} | error: {e.stderr}")
            return []
        except subprocess.TimeoutExpired:
            logger.error(f"get commit filelisttimeout | commit: {commit[:12]}")
            return []
        except Exception as e:
            logger.error(f"get commit file list exception | commit: {commit[:12]} | error: {str(e)}")
            return []

    def _check_files_mentioned_in_error(self, error_id: str, changed_files: List[str]) -> Dict[str, Any]:
        """
        checkfileerrorlog

        Args:
            error_id: errorID
            changed_files: filelist

        Returns:
            checkdict: 
            {
                'mentioned': bool,  # file
                'mentioned_files': List[str],  # filelist
                'total_files': int  # file
            }
        """
        try:
            if not changed_files:
                logger.warning("changed_files , checkfile")
                return {
                    'mentioned': False,
                    'mentioned_files': [],
                    'total_files': 0,
                    'reason': 'no_changed_files'
                }

            logger.debug(f"checkfile | error_id: {error_id[:80]} | files: {len(changed_files)}")

            #  error_id file
            # error_id errorlog, file
            mentioned_files = []

            for file_path in changed_files:
                # getfile()
                file_name = os.path.basename(file_path)

                # checkfile error_id 
                if file_name in error_id or file_path in error_id:
                    mentioned_files.append(file_path)
                    logger.debug(f"  file: {file_path}")

            mentioned = len(mentioned_files) > 0

            logger.info(
                f"filecheck | "
                f"total: {len(changed_files)} | "
                f"mentioned: {len(mentioned_files)} | "
                f"ratio: {len(mentioned_files)/len(changed_files):.1%}"
            )

            if mentioned:
                logger.info(f"  file: {mentioned_files[:5]}")
            else:
                logger.warning(f"  warning: fileerrorlog!")

            return {
                'mentioned': mentioned,
                'mentioned_files': mentioned_files,
                'total_files': len(changed_files),
                'mention_ratio': len(mentioned_files) / len(changed_files) if changed_files else 0
            }

        except Exception as e:
            logger.error(f"file-check failed: {str(e)}")
            logger.error(traceback.format_exc())
            return {
                'mentioned': False,
                'mentioned_files': [],
                'total_files': len(changed_files),
                'error': str(e)
            }

    def _calculate_confidence_level(self, file_check_result: Dict) -> str:
        """
         bisect 

        Args:
            file_check_result: filecheck

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
    """Create VerificationConsumer instance."""
    client = ManticoreClient(
        host=config.get('manticore_host', 'localhost'),
        port=int(config.get('manticore_http_port', '9308'))
    )
    return VerificationConsumer(client, config)
