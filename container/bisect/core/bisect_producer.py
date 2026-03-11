#!/usr/bin/env python3
"""
Bisect Producer - producer component for bisect tasks
Extracted producer-related methods from TaskProcessor
"""

import os
import time
import json
import logging
import shutil
import traceback
import re
import subprocess
from typing import Dict, Any, List, Set, Tuple, Optional
from pathlib import Path
from collections import defaultdict

from lkp_bisect.db.manticore import ManticoreClient

# Import project's structured logging system
import sys
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger
from config import Config
from bisect_utils import (
    smart_split_error_ids,
    extract_git_url_from_full_text_kv,
    extract_commit_from_full_text_kv,
    get_repo_info_from_job_data,
    write_analysis_files
)

# Import core functions from bisect_utils
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from bisect_utils import extract_repo_name_from_url, categorize_bisect_task, format_error_ids
from producer_reporter import ProducerReporter
from lru_cache import LRUCache
from batch_inserter import BatchInserter

# Import Commit Time Service Client
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/services/commit_time_service')
try:
    from client import CommitTimeClient
    COMMIT_TIME_CLIENT_AVAILABLE = True
except ImportError:
    logger.warning("Commit Time Service Client not available, commit age filtering disabled")
    COMMIT_TIME_CLIENT_AVAILABLE = False

class ErrorBisectProducer:
    """Error type bisect task producer"""

    def __init__(self, client: ManticoreClient, config: Dict):
        self.client = client
        self.config = config
        # Use LRU cache instead of simple Set
        self.processed_jobs_cache = LRUCache(max_size=5000)
        self.processed_jobs_cache = LRUCache(max_size=5000)
        self.last_run_time = 0
        self.last_metrics_date = None
        self.last_kernel_test_date = None

        # Import intelligent filter
        from errid_intelligence import ErridIntelligence
        self.errid_intelligence = ErridIntelligence()

        # Initialize reporter (using default producer_stats directory)
        self.reporter = ProducerReporter()

        # Initialize batch inserter with configured batch size
        batch_size = Config.BISECT_PRODUCER_BATCH_SIZE
        self.batch_inserter = BatchInserter(client, batch_size=batch_size)

        # Use configured query time range
        self.query_hours = Config.BISECT_PRODUCER_QUERY_HOURS
        logger.info(f"ErrorBisectProducer initialized | query_hours: {self.query_hours}h | batch_size: {batch_size}")

        # Initialize commit time filter client
        if COMMIT_TIME_CLIENT_AVAILABLE:
            commit_service_url = config.get(
                'commit_time_service_url',
                os.environ.get('COMMIT_TIME_SERVICE_URL', 'http://localhost:8765')
            )
            self.commit_client = CommitTimeClient(commit_service_url)
            self.max_commit_age_days = config.get(
                'max_commit_age_days',
                int(os.environ.get('BISECT_MAX_COMMIT_AGE_DAYS', '365'))
            )
            # Minimum kernel version filter
            self.min_kernel_version = Config.BISECT_MIN_KERNEL_VERSION
            if self.min_kernel_version:
                logger.info(f"Commit filtering enabled | service: {commit_service_url} | max_age: {self.max_commit_age_days} days | min_version: v{self.min_kernel_version}")
            else:
                logger.info(f"Commit age filtering enabled | service: {commit_service_url} | max_age: {self.max_commit_age_days} days | version_filter: disabled")
        else:
            self.commit_client = None
            self.min_kernel_version = None
            logger.warning("Commit filtering not enabled (service unavailable)")

    def _run_script(self, script_path, args=None, description="script"):
        """Generic script execution method - real-time streaming log output"""
        if not os.path.exists(script_path):
            logger.warning(f"{description} not found at: {script_path}")
            return False
            
        logger.info(f"Running {description}: {script_path}")

        # Build command based on script type
        if script_path.endswith('.py'):
            # Python script: use sys.executable
            cmd = [sys.executable, "-u", script_path]  # -u for unbuffered output
        elif script_path.endswith('.sh'):
            # Shell script: use bash to avoid permission issues
            cmd = ['bash', script_path]
        else:
            # Other types: try direct execution
            cmd = [script_path]

        # Add arguments
        if args is not None:
            cmd.extend(args)

        try:
            # Use Popen for real-time output
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,  # Merge stderr into stdout
                text=True,
                bufsize=1,  # Line buffered
                universal_newlines=True
            )
            
            # Read output in real-time
            for line in process.stdout:
                line = line.strip()
                if line:
                    logger.info(f"[{description}] {line}")
            
            # Wait for process to finish
            process.wait(timeout=3600)
            
            if process.returncode == 0:
                logger.info(f"{description} successful.")
                return True
            else:
                logger.error(f"{description} failed (code {process.returncode})")
                return False
                
        except subprocess.TimeoutExpired:
            process.kill()
            logger.error(f"{description} timed out after 3600s")
            return False
        except Exception as e:
            logger.error(f"Error running {description}: {str(e)}")
            return False

    def execute_producer_cycle(self, force_run_scripts=False):
        """
        Optimized producer cycle - simplified version, mainly optimized queries
        
        Args:
            force_run_scripts: whether to force run maintenance scripts (ignore daily limit)
        """
        current_date = time.strftime('%Y-%m-%d')
        lkp_src = os.environ.get('LKP_SRC', '/lkp')

        # === 1. Metrics collection script ===
        # Run once daily, or when forced
        if force_run_scripts or self.last_metrics_date != current_date:
            tracker_script = os.path.join(lkp_src, 'programs/bisect-py/utils/bisect_metrics_tracker.py')
            if self._run_script(tracker_script, ['--collect', '--plot'], "metrics collection"):
                # Only update date marker on successful run in non-force mode to prevent forced runs from affecting auto scheduling
                # Or: update whenever successful? Typically forced run counts as today's run.
                # Strategy: update date marker if run successfully
                self.last_metrics_date = current_date

        # === 2. Daily kernel test script ===
        # Run once daily, or when forced
        if force_run_scripts or self.last_kernel_test_date != current_date:
            kernel_test_script = os.path.join(lkp_src, 'sbin/bisect/kernel_ci/daily_kernel_test.sh')
            if self._run_script(kernel_test_script, None, "daily kernel test script"):
                self.last_kernel_test_date = current_date

        start_time = time.time()
        cycle_timestamp = int(start_time)

        # Initialize statistics (using configured query time)
        stats = {
            'cycle_start_time': cycle_timestamp,
            'time_range_hours': self.query_hours,
            'max_count': 150,     # Limit: max 150 error_ids per job
            'min_priority': 35,   # Set to 35 to include valuable code warnings
            'jobs_queried': 0,
            'jobs_cache_hit': 0,
            'jobs_processed': 0,
            'jobs_filtered_out': 0,
            'total_errids_before_filter': 0,
            'total_errids_after_smart_filter': 0,
            'tasks_db_duplicate': 0,
            'tasks_no_git_url': 0,
            'tasks_filtered_old_commits': 0,  # Tasks filtered by commit age
            'tasks_commit_age_checked': 0,    # Tasks checked for commit age
            'tasks_commit_hash_not_found': 0,  # Tasks where commit hash not found
            'tasks_created_success': 0,
            'tasks_created_failed': 0,
            'filter_method_smart': 0,
            'filter_method_none': 0,
            'batch_queries_count': 0,
            'individual_queries_saved': 0,
            'batch_query_success_rate': 0
        }

        logger.info(f"==" * 40)
        logger.info(f"Error producer cycle started | time: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(start_time))}")
        logger.info(f"==" * 40)

        # Query recent jobs (using configured time range)
        time_range_hours = self.query_hours
        time_threshold = int(time.time() - time_range_hours * 3600)
        from_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(time_threshold))
        to_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime())
        stats['query_time_from'] = from_time
        stats['query_time_to'] = to_time

        logger.info(f"Querying jobs table | time_range: {from_time} to {to_time}")
        logger.info(f"Query filter: exclude bisect intermediate tasks (j.bad_job_id IS NULL)")

        sql_query = f"""
            SELECT id, j.errid, full_text_kv, submit_time
            FROM jobs
            WHERE j.errid IS NOT NULL
            AND j.job_stage = 'finish'
            AND j.job_data_readiness = 'complete'
            AND j.bad_job_id IS NULL
            AND submit_time >= {time_threshold}
            ORDER BY id DESC
            LIMIT 1000
        """

        try:
            result = self.client.sql_select(sql_query)
            stats['jobs_queried'] = len(result) if result else 0
            logger.info(f"Query completed | returned {stats['jobs_queried']} rows")
        except Exception as e:
            logger.error(f"Failed to query jobs table: {str(e)}")
            self._log_producer_stats(stats, start_time)
            return 0

        if not result:
            logger.warning(f"No matching error type jobs data found")
            self._log_producer_stats(stats, start_time)
            return 0

        # ===== Core optimization: batch check commit age first, then process error_ids =====
        all_tasks_to_create = []  # Collect all tasks to create
        unfiltered_jobs = []  # List of unfiltered jobs
        job_data_list = []  # All processed jobs
        filtered_results = {}  # Successfully filtered results {bad_job_id: [(errid, analysis), ...]}

        # Phase 0: collect basic info of all jobs (for batch commit check)
        logger.info("Phase 0: Collecting job basic info...")
        job_info_map = {}  # {job_id: {'full_text_kv': ..., 'git_url': ..., 'commit': ..., 'errids': ...}}
        commit_check_items = []  # List for batch checking

        for item in result:
            try:
                if not item.get("id"):
                    continue

                bad_job_id = str(int(item["id"]))
                full_text_kv = item.get("full_text_kv", "")
                errids = item.get("j.errid", [])

                # Collect all processed job data
                job_data_list.append({
                    'bad_job_id': bad_job_id,
                    'full_text_kv': full_text_kv,
                    'errid_list': errids
                })

                # Cache check
                cache_check_start = time.time()
                if bad_job_id in self.processed_jobs_cache:
                    stats['jobs_cache_hit'] += 1
                    stats.setdefault('cache_check_time_ms', 0)
                    stats['cache_check_time_ms'] += (time.time() - cache_check_start) * 1000
                    continue

                self.processed_jobs_cache.add(bad_job_id)
                stats.setdefault('cache_check_time_ms', 0)
                stats['cache_check_time_ms'] += (time.time() - cache_check_start) * 1000

                # Extract git_url
                git_url_start = time.time()
                git_url = extract_git_url_from_full_text_kv(full_text_kv)
                stats.setdefault('git_url_extract_time_ms', 0)
                stats['git_url_extract_time_ms'] += (time.time() - git_url_start) * 1000

                if not git_url:
                    stats['tasks_no_git_url'] += 1
                    continue

                # Build task filter
                filter_start = time.time()
                should_filter, filter_reason = self.errid_intelligence.should_filter_build_task(full_text_kv, git_url)
                stats.setdefault('filter_time_ms', 0)
                stats['filter_time_ms'] += (time.time() - filter_start) * 1000

                if should_filter:
                    stats.setdefault('build_tasks_filtered', 0)
                    stats['build_tasks_filtered'] += 1
                    logger.debug(f"Filtered build task | job_id: {bad_job_id} | reason: {filter_reason}")
                    continue

                # Extract commit hash
                commit_hash = extract_commit_from_full_text_kv(full_text_kv)

                # Save job info
                job_info_map[bad_job_id] = {
                    'full_text_kv': full_text_kv,
                    'git_url': git_url,
                    'commit': commit_hash,
                    'errids': errids,
                    'item': item
                }

                # If has commit, add to batch check list
                if commit_hash and self.commit_client:
                    commit_check_items.append({
                        'job_id': bad_job_id,
                        'git_url': git_url,
                        'commit': commit_hash
                    })
                elif not commit_hash:
                    stats['tasks_commit_hash_not_found'] += 1
                    unfiltered_jobs.append({
                        'bad_job_id': bad_job_id,
                        'errid_list': [],
                        'reason': 'no_commit_hash',
                        'git_url': git_url,
                        'full_text_kv_sample': full_text_kv[:500] if full_text_kv else ''
                    })
                    # Skip jobs without commit hash
                    del job_info_map[bad_job_id]

            except Exception as e:
                logger.error(f"Phase 0 error processing job: {str(e)}")
                continue

        logger.info(f"Phase 0 completed: collected {len(job_info_map)} valid jobs, {len(commit_check_items)} need commit check")

        # Phase 1: batch check commit age and branch version (key optimization: single network call)
        valid_job_ids = set(job_info_map.keys())  # All valid by default

        if self.commit_client and commit_check_items:
            filter_desc = f"age>{self.max_commit_age_days}days"
            if self.min_kernel_version:
                filter_desc += f" or version<v{self.min_kernel_version}"
            logger.info(f"Phase 1: Batch checking {len(commit_check_items)} commits ({filter_desc})...")
            commit_age_start = time.time()

            try:
                too_old_job_ids, checked_valid_ids = self.commit_client.batch_check_commits(
                    commit_check_items,
                    self.max_commit_age_days,
                    self.min_kernel_version  # Pass minimum kernel version
                )

                stats['tasks_commit_age_checked'] = len(commit_check_items)
                stats['tasks_filtered_old_commits'] = len(too_old_job_ids)

                # Remove old commit jobs from valid list
                valid_job_ids -= too_old_job_ids

                # Record filtered jobs (also add to unfiltered_jobs for tracing)
                for job_id in too_old_job_ids:
                    if job_id in job_info_map:
                        info = job_info_map[job_id]
                        commit = info.get('commit', '')
                        git_url = info.get('git_url', '')
                        logger.info(f"Filtered commit | job_id: {job_id} | commit: {commit[:12] if len(commit) > 12 else commit}...")
                        # Record to unfiltered_jobs for tracing in analysis directory
                        unfiltered_jobs.append({
                            'bad_job_id': job_id,
                            'errid_list': info.get('errids', []),
                            'reason': f'commit_filtered (age>{self.max_commit_age_days}d or version<v{self.min_kernel_version})',
                            'git_url': git_url,
                            'commit': commit,
                            'full_text_kv_sample': info.get('full_text_kv', '')[:500] if info.get('full_text_kv') else ''
                        })
                        del job_info_map[job_id]

            except Exception as e:
                logger.warning(f"Batch commit check failed: {str(e)} | continuing with all jobs")

            stats.setdefault('commit_age_check_time_ms', 0)
            stats['commit_age_check_time_ms'] = (time.time() - commit_age_start) * 1000
            logger.info(f"Phase 1 completed: filtered {stats['tasks_filtered_old_commits']} commits, {len(valid_job_ids)} valid jobs remaining")
        else:
            logger.info("Phase 1: Skipping commit check (no commit client or no check needed)")

        # Phase 2: process error_ids for jobs that passed commit check
        logger.info(f"Phase 2: Processing error_ids for {len(valid_job_ids)} valid jobs...")

        for bad_job_id in valid_job_ids:
            if bad_job_id not in job_info_map:
                continue

            try:
                info = job_info_map[bad_job_id]
                full_text_kv = info['full_text_kv']
                git_url = info['git_url']
                errids = info['errids']

                # Extract and filter error IDs
                if not isinstance(errids, list):
                    unfiltered_jobs.append({
                        'bad_job_id': bad_job_id,
                        'errid_list': [],
                        'reason': 'no_errids'
                    })
                    continue

                if not errids:
                    unfiltered_jobs.append({
                        'bad_job_id': bad_job_id,
                        'errid_list': [],
                        'reason': 'empty_errids'
                    })
                    continue

                stats['jobs_processed'] += 1
                stats['total_errids_before_filter'] += len(errids)

                # Smart filtering
                errid_filter_start = time.time()
                smart_candidates = self.errid_intelligence.filter_errids(
                    errids,
                    max_count=stats['max_count'],
                    min_priority=stats['min_priority']
                )
                stats.setdefault('errid_filter_time_ms', 0)
                stats['errid_filter_time_ms'] += (time.time() - errid_filter_start) * 1000

                if not smart_candidates:
                    stats['jobs_filtered_out'] += 1
                    unfiltered_jobs.append({
                        'bad_job_id': bad_job_id,
                        'errid_list': errids,
                        'reason': 'no_smart_filter_match'
                    })
                    continue

                # Collect successfully filtered tasks
                filtered_results[bad_job_id] = smart_candidates

                # Collect tasks
                for errid, analysis in smart_candidates:
                    all_tasks_to_create.append({
                        'bad_job_id': bad_job_id,
                        'error_id': errid,
                        'git_url': git_url,
                        'priority': analysis.priority,
                        'full_text_kv': full_text_kv
                    })

                stats['filter_method_smart'] += 1
                stats['total_errids_after_smart_filter'] += len(smart_candidates)

            except Exception as e:
                logger.error(f"Phase 2 error processing job: {str(e)}")
                continue

        logger.info(f"Phase 2 completed: collected {len(all_tasks_to_create)} candidate tasks")

        # Phase 3: one-time batch deduplication (key optimization)
        if all_tasks_to_create:
            logger.info(f"Phase 3: Batch deduplication check for {len(all_tasks_to_create)} tasks...")

            # Extract all error_ids
            all_error_ids = [task['error_id'] for task in all_tasks_to_create]

            # Check all error_ids in one query (may need batching if too many)
            existing_error_ids = set()
            batch_size = 500  # 500 per batch

            for i in range(0, len(all_error_ids), batch_size):
                batch = all_error_ids[i:i + batch_size]
                try:
                    query = {
                        "bool": {
                            "must": [
                                {"in": {"error_id": batch}}
                            ]
                        }
                    }
                    # Increase limit to ensure all matching error_ids are found
                    # Even if an error_id has multiple records, we just need to know it exists
                    existing = self.client.search(index="bisect", query=query, limit=10000)
                    if existing:
                        for item in existing:
                            if item.get('error_id'):
                                existing_error_ids.add(item['error_id'])
                except Exception as e:
                    logger.error(f"Batch check failed: {str(e)}")

            stats['tasks_db_duplicate'] = len(existing_error_ids)
            logger.info(f"Deduplication completed: {len(existing_error_ids)} tasks already exist")

            # Phase 4: prepare to create new tasks
            tasks_to_create = []
            for task_data in all_tasks_to_create:
                if task_data['error_id'] in existing_error_ids:
                    continue  # Skip existing

                # Prepare task data
                task = {
                    "bad_job_id": task_data['bad_job_id'],
                    "error_id": task_data['error_id'],
                    "bisect_status": "wait",
                    "git_url": task_data['git_url']
                }

                # Add classification
                category = categorize_bisect_task(task, task_data['full_text_kv'])
                task["category"] = category

                tasks_to_create.append(task)

            # Phase 4: create tasks using batch inserter
            if tasks_to_create:
                logger.info(f"Phase 4: Batch creating {len(tasks_to_create)} new tasks...")
                success_count, failed_count = self.batch_inserter.batch_create_tasks(tasks_to_create)

                stats['tasks_created_success'] = success_count
                stats['tasks_created_failed'] = failed_count

                # Get batch inserter statistics
                batch_stats = self.batch_inserter.get_stats()
                stats['batch_insert_stats'] = batch_stats
                logger.info(f"Batch creation completed | success: {success_count} | failed: {failed_count}")

        # Generate analysis files (summary and filtered/unfiltered JSON)
        if job_data_list:
            try:
                logger.info("Generating analysis files...")
                write_analysis_files(job_data_list, filtered_results, unfiltered_jobs)
                logger.info("Analysis files generated")
            except Exception as e:
                logger.error(f"Failed to generate analysis files: {str(e)}")

        # Memory management - LRU cache handles eviction automatically
        # No manual cleanup needed, LRU has max_size=5000
        if len(self.processed_jobs_cache) > 4500:
            logger.debug(f"Producer cache size: {len(self.processed_jobs_cache)}, "
                        f"evictions: {self.processed_jobs_cache.evictions}")
            # LRU cache automatically evicts least recently used items

        # Output statistics
        self._log_producer_stats(stats, start_time)
        return stats['tasks_created_success']

    def _log_producer_stats(self, stats: dict, start_time: float):
        """Output detailed producer statistics report and save to notification directory"""
        duration = time.time() - start_time

        # Add cache statistics
        cache_stats = self.processed_jobs_cache.get_stats()
        stats['cache_hit_rate'] = cache_stats['hit_rate']
        stats['cache_size'] = cache_stats['size']
        stats['cache_max_size'] = cache_stats['max_size']
        stats['cache_evictions'] = cache_stats['evictions']

        # Calculate average duration
        if stats.get('jobs_processed', 0) > 0:
            stats['avg_filter_time_ms'] = stats.get('filter_time_ms', 0) / stats['jobs_processed']
            stats['avg_git_url_time_ms'] = stats.get('git_url_extract_time_ms', 0) / stats['jobs_processed']
            stats['avg_errid_time_ms'] = stats.get('errid_filter_time_ms', 0) / stats['jobs_processed']
            if stats.get('commit_age_check_time_ms', 0) > 0:
                stats['avg_commit_age_check_ms'] = stats.get('commit_age_check_time_ms', 0) / stats['jobs_processed']

        # Add commit filter config to statistics
        if self.commit_client:
            stats['max_commit_age_days'] = self.max_commit_age_days

        # Use new report generator
        self.reporter.write_report(stats, duration)

        # Write latest status summary
        self.reporter.write_simple_summary(stats)

        # Output performance log
        logger.info(f"Producer performance stats | total_duration: {duration:.2f}s")
        logger.info(f"  cache_hit_rate: {stats['cache_hit_rate']:.2%} | cache_size: {stats['cache_size']}/{cache_stats['max_size']}")
        if stats.get('jobs_processed', 0) > 0:
            logger.info(f"  avg_time | filter: {stats.get('avg_filter_time_ms', 0):.2f}ms | "
                       f"url_extract: {stats.get('avg_git_url_time_ms', 0):.2f}ms | "
                       f"errid_filter: {stats.get('avg_errid_time_ms', 0):.2f}ms")
            if stats.get('avg_commit_age_check_ms', 0) > 0:
                logger.info(f"  commit_age_check: {stats.get('avg_commit_age_check_ms', 0):.2f}ms")

        # Output filter statistics
        if stats.get('tasks_filtered_old_commits', 0) > 0:
            logger.info(f"Commit age filter stats | filtered: {stats['tasks_filtered_old_commits']} | "
                       f"threshold: {self.max_commit_age_days} days")


class PerformanceBisectProducer:
    """Performance type bisect task producer

    Uses midpoint algorithm to compare kernel CI performance test results,
    identify bisectable performance regressions and create tasks.

    Phase 1: Performance monitoring based on kernel CI
    Phase 2: Smart monitoring based on KPI (future expansion)

    Metric prefix convention (ref lkp-stats-type.md):
    - SmallerBetter: lat, jit, pow, cost, mem
    - BiggerBetter: rate
    - KPI metrics use uppercase prefix: LAT, JIT, POW, COST, MEM, RATE
    """

    # Prefix constants (based on lkp-stats-type.md convention)
    SMALLER_BETTER_PREFIXES = {'lat', 'jit', 'pow', 'cost', 'mem'}
    BIGGER_BETTER_PREFIXES = {'rate'}

    def __init__(self, client: ManticoreClient, config: Dict):
        self.client = client
        self.config = config
        self.last_run_time = 0

        # Use config
        self.producer_interval = Config.PERFORMANCE_PRODUCER_INTERVAL_DAYS * 86400
        self.query_hours = Config.PERFORMANCE_PRODUCER_QUERY_HOURS
        self.min_samples = Config.PERFORMANCE_MIN_SAMPLES
        self.default_samples = Config.PERFORMANCE_DEFAULT_SAMPLES

        # Performance test suites
        self.performance_suites = [s.strip() for s in Config.PERFORMANCE_SUITES.split(',')]

        # Baseline config - aligned with kernel-ci KERNEL_TEST_CONFIG
        # Format: {commit: True} means this is a baseline commit
        self.baseline_commits = {
            # openEuler OLK-5.10 baseline
            '5.10.0-216.0.0': True,
            # openEuler OLK-6.6 baseline
            '6.6.0-98.0.0': True,
            # linux/linux-next baseline
            'v6.17': True,
        }

        # Load metric config
        self.metrics_config = self._load_metrics_config()

        # Initialize batch inserter
        self.batch_inserter = BatchInserter(client, batch_size=50)

        # LRU cache for deduplication
        self.processed_pairs_cache = LRUCache(max_size=1000)

        # Initialize reporter
        self.reporter = ProducerReporter(stats_dir='performance_producer_stats')

        # Initialize commit time service client for ancestor checks
        if COMMIT_TIME_CLIENT_AVAILABLE:
            commit_service_url = config.get(
                'commit_time_service_url',
                os.environ.get('COMMIT_TIME_SERVICE_URL', 'http://localhost:8765')
            )
            self.commit_client = CommitTimeClient(commit_service_url)
        else:
            self.commit_client = None

        logger.info(f"PerformanceBisectProducer initialized | "
                   f"query_hours: {self.query_hours}h | "
                   f"interval: {Config.PERFORMANCE_PRODUCER_INTERVAL_DAYS} days | "
                   f"monitored_suites: {self.performance_suites}")

    def _load_metrics_config(self) -> Dict:
        """Load metric config (simplified)

        KPI determination and direction inference now based on lkp-stats-type.md prefix convention:
        - KPI metrics: uppercase prefix (LAT, RATE, JIT, POW, COST, MEM)
        - Direction: lat/jit/pow/cost/mem = -1, rate = +1

        No longer need to load config from meta.yaml or performance_metrics.yaml
        """
        logger.info("Using prefix-based KPI determination (ref lkp-stats-type.md)")
        return {}

    def execute_producer_cycle(self) -> int:
        """Execute a complete performance producer cycle

        Returns:
            Number of tasks created
        """
        start_time = time.time()
        stats = self._init_stats()

        logger.info("=" * 80)
        logger.info(f"Performance bisect producer cycle started | time: {time.strftime('%Y-%m-%d %H:%M:%S')}")
        logger.info("=" * 80)

        try:
            # Phase 1: query performance test jobs
            performance_jobs = self._query_performance_jobs()
            stats['jobs_queried'] = len(performance_jobs)

            if not performance_jobs:
                logger.info("No performance test jobs found")
                self._log_stats(stats, start_time)
                return 0

            logger.info(f"Phase 1 completed: found {len(performance_jobs)} performance test jobs")

            # Phase 2: group by (repo, suite, testbox)
            grouped_jobs = self._group_performance_jobs(performance_jobs)
            stats['groups_found'] = len(grouped_jobs)
            logger.info(f"Phase 2 completed: grouped into {len(grouped_jobs)} groups")

            # Phase 3: identify baseline/current pairs
            comparison_pairs = self._identify_comparison_pairs(grouped_jobs)
            stats['pairs_found'] = len(comparison_pairs)
            logger.info(f"Phase 3 completed: identified {len(comparison_pairs)} comparison pairs")

            # Phase 4: apply midpoint algorithm to filter bisectable pairs
            bisectable_pairs = self._filter_bisectable_pairs(comparison_pairs, stats)
            stats['bisectable_pairs'] = len(bisectable_pairs)
            logger.info(f"Phase 4 completed: {len(bisectable_pairs)} pairs meet bisect criteria")

            # Phase 5: create bisect tasks
            tasks_created = self._create_bisect_tasks(bisectable_pairs, stats)
            stats['tasks_created'] = tasks_created
            logger.info(f"Phase 5 completed: created {tasks_created} performance bisect tasks")

            return tasks_created

        except Exception as e:
            logger.error(f"Performance producer cycle failed: {str(e)}")
            logger.error(traceback.format_exc())
            return 0
        finally:
            self._log_stats(stats, start_time)

    def _init_stats(self) -> Dict:
        """Initialize statistics"""
        return {
            'cycle_start_time': int(time.time()),
            'time_range_hours': self.query_hours,
            'jobs_queried': 0,
            'groups_found': 0,
            'pairs_found': 0,
            'pairs_cache_hit': 0,
            'pairs_insufficient_samples': 0,
            'pairs_not_ancestor': 0,
            'pairs_no_gap': 0,
            'pairs_below_threshold': 0,
            'bisectable_pairs': 0,
            'tasks_db_duplicate': 0,
            'tasks_created': 0,
            'tasks_failed': 0
        }

    def _query_performance_jobs(self) -> List[Dict]:
        """Query performance test jobs

        Query conditions:
        - suite in monitored list
        - job_stage = 'finish', job_health = 'success'
        - submit_time within query time range
        """
        time_threshold = int(time.time() - self.query_hours * 3600)
        suites_sql = "', '".join(self.performance_suites)

        # Build query - directly get j.ss.linux.commit field
        sql_query = f"""
            SELECT id, suite, testbox, submit_time, full_text_kv, j, j.ss.linux.commit as linux_commit
            FROM jobs
            WHERE suite IN ('{suites_sql}')
            AND j.job_stage = 'finish'
            AND j.job_health = 'success'
            AND j.job_data_readiness = 'complete'
            AND submit_time >= {time_threshold}
            ORDER BY submit_time DESC
            LIMIT 5000
        """

        try:
            result = self.client.sql_select(sql_query)
            if not result:
                logger.info(f"SQL query returned empty result | suites: {self.performance_suites}")
                return []

            logger.info(f"SQL query returned {len(result)} raw records")

            # Parse and extract valid job data
            processed_jobs = []
            parse_failures = {'no_commit': 0, 'no_git_url': 0, 'no_stats': 0, 'other': 0}
            suite_counts = defaultdict(int)

            for item in result:
                job_data = self._parse_job_data(item)
                if job_data:
                    processed_jobs.append(job_data)
                    suite_counts[job_data['suite']] += 1

            # Output suite distribution
            if suite_counts:
                logger.info(f"Valid jobs by suite distribution: {dict(suite_counts)}")
            else:
                logger.warning("No valid performance test jobs parsed")

            return processed_jobs

        except Exception as e:
            logger.error(f"Failed to query performance jobs: {str(e)}")
            return []

    def _parse_job_data(self, item: Dict) -> Optional[Dict]:
        """Parse job data

        Extract: commit, git_url, stats, testbox, suite, repo/branch info
        """
        try:
            j_field = item.get('j', {})
            if isinstance(j_field, str):
                import json
                j_field = json.loads(j_field)

            full_text_kv = item.get('full_text_kv', '')

            # Extract commit - prefer linux_commit directly from SQL
            commit = item.get('linux_commit') or self._extract_commit(j_field, full_text_kv)
            if not commit:
                return None

            # Extract git_url
            git_url = extract_git_url_from_full_text_kv(full_text_kv)
            if not git_url:
                return None

            # Extract stats
            stats = j_field.get('stats', {})
            if not stats:
                return None

            # Extract repo/branch info
            repo_name = extract_repo_name_from_url(git_url)
            branch = self._extract_branch(j_field, full_text_kv)

            return {
                'job_id': str(item.get('id')),
                'suite': item.get('suite'),
                'testbox': item.get('testbox', ''),
                'commit': commit,
                'git_url': git_url,
                'repo_name': repo_name,
                'branch': branch or 'master',
                'stats': stats,
                'submit_time': item.get('submit_time'),
                'full_text_kv': full_text_kv,
                'j': j_field
            }

        except Exception as e:
            logger.debug(f"Failed to parse job data: {str(e)}")
            return None

    def _extract_commit(self, j_field: Dict, full_text_kv: str) -> Optional[str]:
        """Extract commit hash"""
        # Try to extract from j field
        if j_field:
            # ss.linux.commit
            commit = j_field.get('ss', {}).get('linux', {}).get('commit')
            if commit:
                return commit

            # program.makepkg.commit
            commit = j_field.get('program', {}).get('makepkg', {}).get('commit')
            if commit:
                return commit

        # Try to extract from full_text_kv
        return extract_commit_from_full_text_kv(full_text_kv)

    def _extract_branch(self, j_field: Dict, full_text_kv: str) -> Optional[str]:
        """Extract branch info"""
        if j_field:
            # program.makepkg.branch
            branch = j_field.get('program', {}).get('makepkg', {}).get('branch')
            if branch:
                return branch

        # Extract from full_text_kv
        for line in full_text_kv.split('\n'):
            if 'branch' in line.lower():
                parts = line.split(':')
                if len(parts) >= 2:
                    return parts[-1].strip()

        return None

    def _group_performance_jobs(self, jobs: List[Dict]) -> Dict[Tuple, List[Dict]]:
        """Group by (repo, suite, testbox)

        Grouping strategy:
        - Keep repo to distinguish different kernel repos (openeuler-kernel vs linux vs linux-next)
        - Remove branch to avoid over-grouping from parse errors
        - Performance comparison is only meaningful on same hardware (testbox)
        """
        groups = defaultdict(list)

        for job in jobs:
            group_key = (
                job['repo_name'],
                job['suite'],
                job['testbox']
            )
            groups[group_key].append(job)

        # Output grouping statistics
        if groups:
            # Count groups per suite
            suite_group_counts = defaultdict(int)
            for (repo, suite, testbox), job_list in groups.items():
                suite_group_counts[suite] += 1
            logger.info(f"Grouping stats | by_suite: {dict(suite_group_counts)}")

        return dict(groups)

    def _identify_comparison_pairs(self, grouped_jobs: Dict[Tuple, List[Dict]]) -> List[Dict]:
        """Identify baseline/current comparison pairs

        Strategy:
        1. baseline: stable version tag (v6.17, 5.10.0-216.0.0)
        2. current: RC/HEAD or dynamic tag
        3. Both baseline and current need at least 3 jobs for linear separability verification
        """
        comparison_pairs = []
        skip_reasons = {'no_baseline': 0, 'no_current': 0, 'insufficient_baseline': 0,
                       'insufficient_current': 0, 'no_metrics': 0}
        MIN_JOBS_REQUIRED = 3

        for group_key, jobs in grouped_jobs.items():
            repo_name, suite, testbox = group_key

            # Separate baseline and current jobs
            baseline_jobs = []
            current_jobs = []

            for job in jobs:
                commit = job['commit']
                if self._is_baseline_commit(commit):
                    baseline_jobs.append(job)
                else:
                    current_jobs.append(job)

            if not baseline_jobs:
                skip_reasons['no_baseline'] += 1
                commits = list(set(j['commit'][:16] for j in jobs[:5]))
                logger.info(f"Skipping group {repo_name}/{suite}/{testbox}: no baseline | commits: {commits}")
                continue

            if not current_jobs:
                skip_reasons['no_current'] += 1
                commits = list(set(j['commit'][:16] for j in jobs[:5]))
                logger.info(f"Skipping group {repo_name}/{suite}/{testbox}: no current | commits: {commits}")
                continue

            # Check if enough baseline jobs
            if len(baseline_jobs) < MIN_JOBS_REQUIRED:
                skip_reasons['insufficient_baseline'] += 1
                logger.info(f"Skipping group {repo_name}/{suite}/{testbox}: insufficient baseline jobs "
                           f"({len(baseline_jobs)}<{MIN_JOBS_REQUIRED})")
                continue

            # Check if enough current jobs
            if len(current_jobs) < MIN_JOBS_REQUIRED:
                skip_reasons['insufficient_current'] += 1
                logger.info(f"Skipping group {repo_name}/{suite}/{testbox}: insufficient current jobs "
                           f"({len(current_jobs)}<{MIN_JOBS_REQUIRED})")
                continue

            # Find numeric metrics common to all jobs
            all_jobs = baseline_jobs + current_jobs
            common_metrics = set(all_jobs[0]['stats'].keys())
            for job in all_jobs[1:]:
                common_metrics &= set(job['stats'].keys())

            # Filter to keep only numeric metrics starting with suite
            valid_metrics = []
            sample_stats = baseline_jobs[0]['stats']
            for metric in common_metrics:
                if not metric.startswith(f"{suite}."):
                    continue
                try:
                    float(sample_stats[metric])
                    valid_metrics.append(metric)
                except (TypeError, ValueError):
                    pass

            if not valid_metrics:
                skip_reasons['no_metrics'] += 1
                logger.info(f"Group {repo_name}/{suite}/{testbox}: no common numeric metrics")
                continue

            # Create pair: include all baseline and current jobs
            baseline_commit = baseline_jobs[0]['commit']
            current_commit = current_jobs[0]['commit']

            comparison_pairs.append({
                'group_key': group_key,
                'metrics': valid_metrics,
                'suite': suite,
                'baseline_jobs': baseline_jobs,
                'current_jobs': current_jobs,
                'git_url': baseline_jobs[0]['git_url'],
                'baseline_commit': baseline_commit,
                'current_commit': current_commit
            })

            logger.info(f"Group {repo_name}/{suite}/{testbox}: pair created | "
                       f"{len(valid_metrics)} metrics | "
                       f"baseline: {baseline_commit[:12]} ({len(baseline_jobs)} jobs) | "
                       f"current: {current_commit[:12]} ({len(current_jobs)} jobs)")

        # Output skip reason statistics
        if any(skip_reasons.values()):
            logger.info(f"Pair skip stats | no_baseline: {skip_reasons['no_baseline']} | "
                       f"no_current: {skip_reasons['no_current']} | "
                       f"insufficient_baseline: {skip_reasons['insufficient_baseline']} | "
                       f"insufficient_current: {skip_reasons['insufficient_current']} | "
                       f"no_metrics: {skip_reasons['no_metrics']}")

        return comparison_pairs

    def _is_baseline_commit(self, commit: str) -> bool:
        """Determine if commit is a baseline commit

        Uses configured baseline commits, aligned with kernel-ci KERNEL_TEST_CONFIG:
        - baseline: fixed stable versions (5.10.0-216.0.0, 6.6.0-98.0.0, v6.17)
        - current: dynamically obtained latest versions (5.10.0-295.0.0, 6.6.0-132.0.0, v6.18-rc7, next-*)
        """
        # Directly look up configured baseline commits
        return commit in self.baseline_commits

    def _filter_bisectable_pairs(self, pairs: List[Dict], stats: Dict) -> List[Dict]:
        """Apply midpoint algorithm to filter bisectable pairs

        Check all metrics in each pair, keep metrics with performance gap

        Improvements:
        1. Use database query to get all available samples, not just current cycle jobs
        2. With too much variance, midpoint check naturally fails, cannot bisect
        """
        bisectable = []

        # Per-suite diagnostic stats
        suite_stats = defaultdict(lambda: {
            'pairs': 0,
            'total_metrics': 0,
            'kpi_metrics': 0,
            'non_kpi_metrics': 0,
            'insufficient_samples': 0,
            'no_gap': 0,
            'has_gap': 0,
            'bisectable': 0
        })

        for pair in pairs:
            try:
                # Get testbox (extract from group_key)
                testbox = pair['group_key'][2]

                # Check cache
                pair_key = self._generate_pair_key(pair)
                if pair_key in self.processed_pairs_cache:
                    stats['pairs_cache_hit'] += 1
                    continue

                suite = pair['suite']
                baseline_commit = pair['baseline_commit']
                current_commit = pair['current_commit']
                git_url = pair.get('git_url')

                # Ancestor validation: ensure baseline is ancestor of current
                if self.commit_client and git_url:
                    try:
                        is_anc = self.commit_client.is_ancestor(git_url, baseline_commit, current_commit)
                        if is_anc is False:
                            stats['pairs_not_ancestor'] += 1
                            logger.warning(f"Skipping non-ancestor pair | {suite}/{testbox} | "
                                         f"baseline: {baseline_commit[:12]} | current: {current_commit[:12]}")
                            continue
                        # is_anc is None means service error — continue gracefully
                    except Exception as e:
                        logger.warning(f"Ancestor check failed, continuing | error: {str(e)}")

                suite_stats[suite]['pairs'] += 1
                suite_stats[suite]['total_metrics'] += len(pair['metrics'])

                # Iterate all metrics, find ones with performance gap
                metrics_with_gap = []
                for metric in pair['metrics']:
                    # Only process KPI metrics (uppercase prefix)
                    if not self._is_kpi_metric(metric):
                        suite_stats[suite]['non_kpi_metrics'] += 1
                        continue

                    suite_stats[suite]['kpi_metrics'] += 1

                    # Query all available samples from database (not just current cycle jobs)
                    v1_samples = self._query_all_samples_from_db(baseline_commit, suite, testbox, metric)
                    v2_samples = self._query_all_samples_from_db(current_commit, suite, testbox, metric)

                    # Verify sample count (need at least 3 samples for linear separability verification)
                    if len(v1_samples) < 3 or len(v2_samples) < 3:
                        stats['pairs_insufficient_samples'] += 1
                        suite_stats[suite]['insufficient_samples'] += 1
                        logger.debug(f"Insufficient samples | {suite}/{testbox}/{metric} | "
                                    f"v1={len(v1_samples)}, v2={len(v2_samples)} (need>=3)")
                        continue

                    # Check performance gap (midpoint algorithm: v1_max < v2_min)
                    has_gap, gap_info = self._check_performance_gap(v1_samples, v2_samples)

                    if has_gap:
                        suite_stats[suite]['has_gap'] += 1
                        metrics_with_gap.append({
                            'metric': metric,
                            'gap_info': gap_info,
                            'v1_samples': v1_samples,
                            'v2_samples': v2_samples
                        })
                    else:
                        suite_stats[suite]['no_gap'] += 1
                        # Diagnostic: show why there is no gap
                        v1_min, v1_max = min(v1_samples), max(v1_samples)
                        v2_min, v2_max = min(v2_samples), max(v2_samples)
                        logger.debug(f"Range overlap no gap | {suite}/{testbox}/{metric} | "
                                    f"v1=[{v1_min:.2f}, {v1_max:.2f}], v2=[{v2_min:.2f}, {v2_max:.2f}]")

                if not metrics_with_gap:
                    stats['pairs_no_gap'] += 1
                    continue

                suite_stats[suite]['bisectable'] += 1

                # Keep metrics with gap info
                pair['metrics_with_gap'] = metrics_with_gap
                bisectable.append(pair)

                # Add to cache
                self.processed_pairs_cache.add(pair_key)

                # Log: show metrics with gap
                for m in metrics_with_gap[:3]:  # Show up to 3
                    logger.info(f"Found bisectable | {pair['suite']}/{testbox}/{pair['baseline_commit'][:8]}..{pair['current_commit'][:8]} | "
                               f"{m['metric'].split('.')[-1]}: {m['gap_info']['change_percent']:.1f}% | "
                               f"samples: v1={len(m['v1_samples'])}, v2={len(m['v2_samples'])}")

            except Exception as e:
                logger.warning(f"Error processing pair: {str(e)}")
                continue

        # Output filter statistics
        if pairs:
            logger.info(f"Midpoint filter stats | total_pairs: {len(pairs)} | "
                       f"cache_hit: {stats['pairs_cache_hit']} | "
                       f"no_gap: {stats['pairs_no_gap']} | "
                       f"bisectable: {len(bisectable)}")

        # Output per-suite diagnostic stats
        logger.info("=" * 60)
        logger.info("Per-suite diagnostic stats:")
        logger.info("=" * 60)
        for suite, ss in sorted(suite_stats.items()):
            logger.info(f"  {suite}:")
            logger.info(f"    pairs: {ss['pairs']}, total_metrics: {ss['total_metrics']}")
            logger.info(f"    kpi_metrics: {ss['kpi_metrics']}, non_kpi_skipped: {ss['non_kpi_metrics']}")
            logger.info(f"    insufficient_samples: {ss['insufficient_samples']}, range_overlap: {ss['no_gap']}")
            logger.info(f"    has_gap: {ss['has_gap']}, bisectable_pairs: {ss['bisectable']}")
        logger.info("=" * 60)

        return bisectable

    def _generate_pair_key(self, pair: Dict) -> str:
        """Generate unique identifier for pair"""
        return f"{pair['baseline_commit']}_{pair['current_commit']}_{pair['suite']}"

    def _collect_samples(self, job: Dict, metric: str) -> List[float]:
        """Collect metric samples from a single job"""
        samples = []
        stats = job.get('stats', {})

        if metric in stats:
            try:
                value = float(stats[metric])
                samples.append(value)
            except (ValueError, TypeError):
                pass

        return samples

    def _collect_samples_from_list(self, jobs: List[Dict], metric: str) -> List[float]:
        """Collect metric samples from multiple jobs"""
        samples = []

        for job in jobs:
            job_samples = self._collect_samples(job, metric)
            samples.extend(job_samples)

        return samples

    def _query_all_samples_from_db(self, commit: str, suite: str, testbox: str, metric: str) -> List[float]:
        """Query all samples for specified commit/suite/testbox/metric from database

        Use all available samples to calculate range, ensuring midpoint accuracy
        """
        sql = f"""
            SELECT j
            FROM jobs
            WHERE j.ss.linux.commit = '{commit}'
            AND suite = '{suite}'
            AND testbox = '{testbox}'
            AND j.job_stage = 'finish'
            AND j.job_health = 'success'
            AND j.job_data_readiness = 'complete'
            ORDER BY submit_time DESC
            LIMIT 100
        """

        try:
            result = self.client.sql_select(sql)
            if not result:
                return []

            samples = []
            for item in result:
                j = item.get('j', {})
                if isinstance(j, str):
                    try:
                        j = json.loads(j)
                    except json.JSONDecodeError:
                        continue

                stats = j.get('stats', {})
                if metric in stats:
                    try:
                        value = float(stats[metric])
                        samples.append(value)
                    except (ValueError, TypeError):
                        pass

            return samples
        except Exception as e:
            logger.warning(f"Failed to query samples: {commit[:8]}/{suite}/{testbox}/{metric} - {e}")
            return []

    def _is_kpi_metric(self, metric: str) -> bool:
        """Determine if metric is a KPI metric (uppercase prefix)

        Based on lkp-stats-type.md convention:
        - Lowercase prefix (lat, rate) = regular metric
        - Uppercase prefix (LAT, RATE) = KPI metric

        Metric format: {suite}.{PREFIX}.{name}...
        Example: lmbench.LAT.CTX.8P.64K.latency.us (KPI)
                 lmbench.lat.ctx.latency.us (not KPI)
        """
        parts = metric.split('.')

        # Find the prefix part
        all_prefixes = self.SMALLER_BETTER_PREFIXES | self.BIGGER_BETTER_PREFIXES
        for part in parts:
            if part.lower() in all_prefixes:
                # Uppercase = KPI
                return part.isupper()

        return False

    def _check_performance_gap(self, v1_samples: List[float], v2_samples: List[float]) -> Tuple[bool, Dict]:
        """Check if performance samples have a clear gap for bisect

        Midpoint algorithm logic:
        - v1_max < v2_min OR v2_max < v1_min
        - Calculate midpoint as bisect decision threshold
        """
        v1_min, v1_max = min(v1_samples), max(v1_samples)
        v2_min, v2_max = min(v2_samples), max(v2_samples)

        # Check non-overlapping ranges
        has_gap = (v1_max < v2_min) or (v2_max < v1_min)

        if not has_gap:
            return False, {}

        # Determine direction and calculate midpoint
        if v1_max < v2_min:
            # Regression: v1 better (smaller) -> v2 worse (larger)
            mid_point = (v1_max + v2_min) / 2
            direction = 'worse'
            change_percent = ((v2_min - v1_max) / v1_max) * 100 if v1_max != 0 else 0
        else:
            # Improvement: v2 better (smaller) -> v1 worse (larger)
            mid_point = (v2_max + v1_min) / 2
            direction = 'better'
            change_percent = ((v1_min - v2_max) / v2_max) * 100 if v2_max != 0 else 0

        return True, {
            'mid_point': mid_point,
            'direction': direction,
            'v1_range': (v1_min, v1_max),
            'v2_range': (v2_min, v2_max),
            'change_percent': change_percent
        }

    def _create_bisect_tasks(self, bisectable_pairs: List[Dict], stats: Dict) -> int:
        """Create tasks for bisectable pairs

        Create an independent task for each bisectable metric
        """
        if not bisectable_pairs:
            return 0

        tasks_to_create = []

        for pair in bisectable_pairs:
            # Iterate each metric with performance gap, create independent task for each
            for metric_info in pair.get('metrics_with_gap', []):
                try:
                    metric = metric_info['metric']

                    # Check if task for this metric already exists
                    if self._task_exists_for_metric(pair, metric):
                        stats['tasks_db_duplicate'] += 1
                        continue

                    # Build task document
                    task = self._build_task_document(pair, metric_info)
                    if task:
                        tasks_to_create.append(task)

                except Exception as e:
                    logger.warning(f"Error creating task: {str(e)}")
                    stats['tasks_failed'] += 1
                    continue

        if not tasks_to_create:
            return 0

        # Batch insert
        success_count, failed_count = self.batch_inserter.batch_create_tasks(tasks_to_create)

        stats['tasks_failed'] += failed_count
        return success_count

    def _task_exists_for_metric(self, pair: Dict, metric: str) -> bool:
        """Check if task for specific metric already exists in database"""
        try:
            query = {
                "bool": {
                    "must": [
                        {"equals": {"bisect_metric": metric}},
                        {"equals": {"category": "benchmark"}}
                    ]
                }
            }

            # Check baseline and current commit
            existing = self.client.search(index="bisect", query=query, limit=10)

            if existing:
                for item in existing:
                    j_field = item.get('j', {})
                    if isinstance(j_field, str):
                        import json
                        j_field = json.loads(j_field)

                    if (j_field.get('baseline_commit') == pair['baseline_commit'] and
                        j_field.get('current_commit') == pair['current_commit']):
                        return True

            return False

        except Exception as e:
            logger.debug(f"Failed to check task existence: {str(e)}")
            return False

    def _build_task_document(self, pair: Dict, metric_info: Dict) -> Dict:
        """Build bisect task document

        Args:
            pair: pair info (baseline_job, current_jobs, git_url, suite, commits)
            metric_info: metric info (metric, gap_info, v1_samples, v2_samples)
        """
        metric = metric_info['metric']
        gap_info = metric_info['gap_info']
        v1_samples = metric_info['v1_samples']
        v2_samples = metric_info['v2_samples']

        # good/bad based on chronological order, not performance direction
        # - good_commit: older commit (baseline, ancestor)
        # - bad_commit: newer commit (current, descendant)
        # Performance direction (worse/better) stored in performance_change_type
        good_commit = pair['baseline_commit']
        bad_job_id = pair['current_jobs'][0]['job_id']

        # Get metric direction
        metric_direction = self._get_metric_direction(pair['suite'], metric)

        task = {
            'bad_job_id': bad_job_id,
            'bisect_metric': metric,
            'direction': gap_info['direction'],
            'category': 'benchmark',
            'git_url': pair['git_url'],
            'bisect_status': 'wait',
            'submit_time': int(time.time()),
            'j': {
                'good_commit': good_commit,
                'bad_commit': pair['current_commit'],
                'mid_point': gap_info['mid_point'],
                'metric_direction': metric_direction,
                'v1_samples': v1_samples,
                'v2_samples': v2_samples,
                'v1_range': list(gap_info['v1_range']),
                'v2_range': list(gap_info['v2_range']),
                'change_percent': gap_info['change_percent'],
                'performance_change_type': gap_info['direction'],
                'baseline_commit': pair['baseline_commit'],
                'current_commit': pair['current_commit'],
                'suite': pair['suite'],
                'testbox': pair['group_key'][2],  # group_key = (repo_name, suite, testbox)
                'source': 'performance_producer',
                'created_at': int(time.time())
            }
        }

        return task

    def _get_metric_direction(self, suite: str, metric: str) -> int:
        """Get metric optimization direction (based on prefix convention)

        Based on lkp-stats-type.md convention, infer direction from metric prefix:
        - lat/jit/pow/cost/mem prefix: -1 (SmallerBetter)
        - rate prefix: +1 (BiggerBetter)

        +1 = bigger is better (throughput, IOPS, bandwidth)
        -1 = smaller is better (latency, jitter, power)

        Metric format: {suite}.{PREFIX}.{name}...
        Example: lmbench.LAT.CTX.8P.64K.latency.us
        """
        # Extract prefix: skip suite part
        # metric may be "LAT.CTX.8P.64K.latency.us" or "lmbench.LAT.CTX.8P.64K.latency.us"
        parts = metric.split('.')

        # Find prefix position
        prefix = None
        for part in parts:
            part_lower = part.lower()
            if part_lower in self.SMALLER_BETTER_PREFIXES or part_lower in self.BIGGER_BETTER_PREFIXES:
                prefix = part_lower
                break

        if prefix:
            if prefix in self.SMALLER_BETTER_PREFIXES:
                return -1
            if prefix in self.BIGGER_BETTER_PREFIXES:
                return 1

        # Fallback: guess from metric name keywords
        metric_lower = metric.lower()
        if any(kw in metric_lower for kw in ['lat', 'time', 'latency', 'jit', 'cost']):
            return -1
        if any(kw in metric_lower for kw in ['throughput', 'iops', 'bw', 'bandwidth', 'rate', 'score']):
            return 1

        return 0  # Unknown

    def _log_stats(self, stats: Dict, start_time: float):
        """Output statistics report"""
        duration = time.time() - start_time

        logger.info("=" * 80)
        logger.info("Performance Bisect Producer Statistics Report")
        logger.info("=" * 80)
        logger.info(f"Total duration: {duration:.2f}s")
        logger.info(f"Query time range: {stats['time_range_hours']}h")
        logger.info(f"Jobs queried: {stats['jobs_queried']}")
        logger.info(f"Groups found: {stats['groups_found']}")
        logger.info(f"Comparison pairs: {stats['pairs_found']}")
        logger.info(f"  - cache_hit: {stats['pairs_cache_hit']}")
        logger.info(f"  - not_ancestor: {stats['pairs_not_ancestor']}")
        logger.info(f"  - insufficient_samples: {stats['pairs_insufficient_samples']}")
        logger.info(f"  - no_gap: {stats['pairs_no_gap']}")
        logger.info(f"  - below_threshold: {stats['pairs_below_threshold']}")
        logger.info(f"Bisectable pairs: {stats['bisectable_pairs']}")
        logger.info(f"Tasks created: {stats['tasks_created']}")
        logger.info(f"  - db_duplicate: {stats['tasks_db_duplicate']}")
        logger.info(f"  - failed: {stats['tasks_failed']}")
        logger.info("=" * 80)

        # Use reporter to save detailed stats
        try:
            self.reporter.write_report(stats, duration)
        except Exception as e:
            logger.debug(f"Failed to save statistics report: {str(e)}")

