import os
import time
import threading
import re
import subprocess
import shutil
import hashlib
import traceback
import random
import signal
import sys
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
from pathlib import Path
from collections import defaultdict

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/core')
from log_config import logger, StructuredLogger
from errid_intelligence import ErridIntelligence
from notification_writer import NotificationWriter
from bisect_utils import (
    _create_task_document,
    _generate_task_id,
    smart_split_error_ids,
    extract_git_url_from_full_text_kv,
    get_repo_info_from_job_data,
    write_analysis_files,
    extract_repo_name_from_url,
    categorize_bisect_task,
    format_error_ids,
    validate_task_data,
    batch_check_existing_tasks,
    get_bisect_statistics,
    cleanup_task_workspace,
    mark_similar_wait_tasks_for_verification,
    mark_introduced_errid_tasks_for_verification
)
from repo_manager import SharedRepoManager
from config import Config

sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from manticore_simple import ManticoreClient
from py_bisect import GitBisect

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/validators')
from success_task_validator import SuccessTaskValidator
from head_validator import HeadValidator

from bisect_producer import ErrorBisectProducer, PerformanceBisectProducer
from bisect_consumer import BisectConsumer




class TaskProcessor:


    def _register_signal_handlers(self):
        """Register signal handlers"""
        signal.signal(signal.SIGINT, self._handle_exit_signal)
        signal.signal(signal.SIGTERM, self._handle_exit_signal)
        logger.info("Exit signal handlers registered")

    def _handle_exit_signal(self, signum, frame):
        """Signal handler callback - fix recursion issue"""
        if self.exit_requested:
            return

        self.exit_requested = True
        logger.warning(f"Received termination signal {signum}, starting cleanup...")
        self.running = False

        # Close thread pool (blocking)
        if hasattr(self, 'thread_pool'):
            self.thread_pool.shutdown(wait=True, cancel_futures=True)
            logger.info("Thread pool closed")

        # Clean up interrupted tasks
        self._cleanup_interrupted_tasks()

        # Safe exit
        logger.info("Cleanup completed, program will exit")

    def _reset_stuck_tasks_on_startup(self):
        """
        Reset tasks stuck in intermediate states on container startup

        Reset rules:
        - processing -> wait (container restart, thread pool tasks lost, need re-execution)
        - verifying -> wait (container restart, verification job status unreliable, need re-execution)

        Note:
        - Uses direct UPDATE statements to avoid SELECT LIMIT issues
        - Cleans up residual workspace directories on filesystem
        """
        try:
            logger.info("Container startup: checking and resetting stuck tasks...")

            current_time = int(time.time())

            # Directly UPDATE all processing tasks to wait (preserve j field, keep good_commit etc.)
            processing_update_sql = f"""
                UPDATE bisect
                SET bisect_status = 'wait', updated_at = {current_time}
                WHERE bisect_status = 'processing'
            """
            processing_result = self.client.sql_raw(processing_update_sql)
            processing_reset = processing_result[0].get('total', 0) if processing_result and len(processing_result) > 0 else 0

            # Directly UPDATE all verifying tasks to wait (preserve j field, keep verification info)
            verifying_update_sql = f"""
                UPDATE bisect
                SET bisect_status = 'wait', updated_at = {current_time}
                WHERE bisect_status = 'verifying'
            """
            verifying_result = self.client.sql_raw(verifying_update_sql)
            verifying_reset = verifying_result[0].get('total', 0) if verifying_result and len(verifying_result) > 0 else 0

            # Clean up all workspace directories starting with digits (task residuals)
            cleaned_dirs = 0
            if hasattr(self, 'repo_manager') and self.repo_manager:
                try:
                    base_dir = self.repo_manager.REPO_BASE_DIR
                    if os.path.exists(base_dir):
                        for entry in os.listdir(base_dir):
                            # Task workspace directory names are digits (task_id)
                            if entry.isdigit():
                                task_dir = os.path.join(base_dir, entry)
                                if os.path.isdir(task_dir):
                                    shutil.rmtree(task_dir, ignore_errors=True)
                                    cleaned_dirs += 1
                except Exception as e:
                    logger.warning(f"Failed to clean up residual directory: {str(e)}")

            logger.warning(
                f"Container startup reset completed | "
                f"processing→wait: {processing_reset} | "
                f"verifying→wait: {verifying_reset} | "
                f"cleaned_dirs: {cleaned_dirs}"
            )

        except Exception as e:
            logger.error(f"Container startup task reset failed: {str(e)}")
            logger.error(traceback.format_exc())



    def __init__(self):
        self._init_databases()
        self.running = True
        self.exit_requested = False
        self._register_signal_handlers()

        # New: Initialize repository manager (must be before _reset_stuck_tasks_on_startup)
        self.repo_manager = SharedRepoManager()
        logger.info("Shared repository manager initialized")

        # Reset stuck tasks on container restart (after repo_manager init)
        self._reset_stuck_tasks_on_startup()

        # New: Initialize intelligent filter
        self.errid_intelligence = ErridIntelligence()
        logger.info("Intelligent Error ID filter initialized")

        # Enhanced Error ID Parser removed - no longer using similarity matching

        # New: Initialize notification writer
        self.notification_writer = NotificationWriter(notification_dir=Config.NOTIFICATION_DIR)
        logger.info(f"Notification writer initialized | dir: {Config.NOTIFICATION_DIR}")

        # Add test logs
        logger.debug("DEBUG test log: initialization started")
        logger.info("INFO test log: initialization started")
        
        # Producer optimization: Cache processed tasks
        self.processed_jobs_cache = set()  # Cache processed bad_job_id
        self.last_producer_run = 0  # Last producer run time
        self.producer_interval = Config.BISECT_PRODUCER_CYCLE_HOURS * 3600

        # Add job info cache
        self._job_info_cache = {}
        self._job_info_cache_lock = threading.Lock()
        self._job_cache_ttl = 1800  # 30 min cache

        # Success task cache removed - no longer using similarity matching

        # Success task signature cache (optimize _find_successful_task_by_signature high-frequency queries)
        self._success_signature_cache = {}  # {signature: task_info}
        self._success_cache_ttl = 3600  # 1 hour cache
        self._success_cache_last_refresh = 0
        self._success_cache_lock = threading.Lock()
        logger.info("Success task signature cache initialized (TTL: 1 hour)")

        # Process pool initialization
        self._config = {
            "manticore_host": os.environ.get('MANTICORE_HOST', 'localhost'),
            "manticore_http_port": os.environ.get('MANTICORE_WRITE_PORT', '9308'),
            "notification_dir": Config.NOTIFICATION_DIR,
            # Verification configuration
            "parallel_verification_jobs": Config.PARALLEL_VERIFICATION_JOBS,
            "verification_batch_size": Config.VERIFICATION_BATCH_SIZE,
            # HEAD check configuration
            "head_check_batch_size": Config.HEAD_CHECK_BATCH_SIZE
        }

        # Get configuration values and apply safety limits
        requested_threads = Config.BISECT_THREADS
        worker_count = min(requested_threads, Config.MAX_THREADS)

        # Add detailed configuration debug info
        cpu_count = os.cpu_count()
        max_threads_calc = min(32, cpu_count * 4)
        bisect_threads_env = os.environ.get('BISECT_THREADS', 'NOT_SET')

        logger.debug(f"DEBUG test log: requested_threads={requested_threads}, actual_threads={worker_count}")
        logger.info(f"INFO test log: requested_threads={requested_threads}, actual_threads={worker_count}")
        
        # Warn about over-configuration
        if requested_threads > Config.MAX_THREADS:
            logger.warning(
                f"Requested thread count ({requested_threads}) exceeds safety limit ({Config.MAX_THREADS}), "
                f"automatically limited to {Config.MAX_THREADS} threads"
            )
        
        # Initialize thread pool
        self.thread_pool = ThreadPoolExecutor(
            max_workers=worker_count,
            thread_name_prefix="BisectWorker"
        )
        # Backpressure: Limit pending tasks to prevent memory explosion
        # Only allow 1.5x worker count to reduce processing queue size
        self.task_semaphore = threading.BoundedSemaphore(int(worker_count * 1.5))
        self.task_futures = []
        
        # Add producer lock for concurrency control
        self.producer_lock = threading.Lock()
        
        # Add execution lock for consumer tasks - task_id based lock
        self.active_task_locks = set()  # Store task_ids being processed
        self.active_task_locks_lock = threading.Lock()

        # Initialize GitBisect instance for reuse (stateless utility methods only)
        self.bisect_instance = GitBisect(logger)
        logger.info("GitBisect instance initialized for utility methods")

        logger.info(f"Thread pool initialized | worker_count: {worker_count} (config: {requested_threads})")

        # Clean up old repositories at startup
        logger.info("Performing initial cleanup of old repositories at startup...")
        self._clean_old_repos(max_age_days=3)


    def _init_databases(self):
        """Initialize ManticoreSearch HTTP client"""
        config = {
            "host": os.environ.get('MANTICORE_HOST', 'localhost'),
            "http_port": int(os.environ.get('MANTICORE_WRITE_PORT', '9308'))
        }
        self.client = ManticoreClient(
            host=config['host'],
            port=config['http_port']
        )

    def add_bisect_task_batch(self, task_data_list, priority: int = None):
        """Batch add bisect tasks - optimized to reduce query storms"""
        if not task_data_list:
            return []

        results = []
        start_time = time.time()

        logger.info(f"Starting batch add of {len(task_data_list)} tasks")

        # Phase 1: batch validate all task data
        validated_tasks = []
        for task_data in task_data_list:
            try:
                validated = validate_task_data(task_data)
                if priority is not None:
                    validated['priority'] = priority
                validated_tasks.append(validated)
            except Exception as e:
                logger.error(f"Task validation failed: {str(e)}")
                results.append({'status': 'error', 'message': str(e)})

        if not validated_tasks:
            return results

        # Phase 2: batch check duplicates (single query for all)
        error_ids = [t.get("error_id") for t in validated_tasks if t.get("error_id")]
        metric_tasks = [(t.get("bisect_metric"), t.get("bad_job_id"))
                       for t in validated_tasks if t.get("bisect_metric")]

        existing_error_ids = set()
        existing_metrics = set()

        # Batch query existing error_ids
        if error_ids:
            try:
                query = {
                    "bool": {
                        "must": [
                            {"in": {"error_id": error_ids}}
                        ]
                    }
                }
                existing = self.client.search(
                    index="bisect",
                    query=query,
                    limit=len(error_ids)
                )
                if existing:
                    existing_error_ids = {item.get('error_id') for item in existing if item.get('error_id')}
                    logger.info(f"Batch dedup: found {len(existing_error_ids)} existing error_ids")
            except Exception as e:
                logger.error(f"Batch check error_ids failed: {str(e)}")

        # Batch query existing metrics
        if metric_tasks:
            for metric, job_id in metric_tasks:
                try:
                    query = {
                        "bool": {
                            "must": [
                                {"equals": {"bisect_metric": metric}},
                                {"equals": {"bad_job_id": job_id}}
                            ]
                        }
                    }
                    existing = self.client.search(index="bisect", query=query, limit=1)
                    if existing and len(existing) > 0:
                        existing_metrics.add((metric, job_id))
                except Exception as e:
                    logger.error(f"Check metric task failed: {str(e)}")

        # Phase 3: batch create non-existing tasks
        created_count = 0
        duplicate_count = 0
        failed_count = 0

        for validated in validated_tasks:
            # Check for duplicates
            if validated.get("error_id") and validated["error_id"] in existing_error_ids:
                results.append({'status': 'duplicate', 'message': 'Task already exists'})
                duplicate_count += 1
                continue

            if validated.get("bisect_metric"):
                metric_key = (validated["bisect_metric"], validated["bad_job_id"])
                if metric_key in existing_metrics:
                    results.append({'status': 'duplicate', 'message': 'Task already exists'})
                    duplicate_count += 1
                    continue

            # Generate task_id
            if validated.get("error_id"):
                task_identifier = f"error_id='{validated['error_id']}'"
            else:
                task_identifier = f"bisect_metric='{validated['bisect_metric']}'"

            task_id = _generate_task_id(validated["bad_job_id"], task_identifier)

            # Create task document
            task_doc = _create_task_document(validated)

            # Set priority
            if priority is not None:
                task_doc["priority_level"] = priority

            # Process git_url and classification
            if "git_url" in validated and validated["git_url"]:
                task_doc["git_url"] = validated["git_url"]
            else:
                # Try to get from cache or full_text_kv
                task_doc["git_url"] = ""

            # Auto classify
            category = categorize_bisect_task(validated, validated.get("full_text_kv", ""))
            task_doc["category"] = category

            # Clean null fields
            for key, value in task_doc.items():
                if value is None:
                    if key in ['submit_time', 'updated_at', 'start_time', 'end_time']:
                        task_doc[key] = 0
                    else:
                        task_doc[key] = ''

            # Insert to database
            try:
                result = self.client.insert("bisect", task_id, task_doc)
                if result:
                    results.append({'status': 'created', 'message': 'Task created successfully'})
                    created_count += 1
                else:
                    results.append({'status': 'failed', 'message': 'Failed to insert task'})
                    failed_count += 1
            except Exception as e:
                results.append({'status': 'error', 'message': str(e)})
                failed_count += 1

        duration = time.time() - start_time
        logger.info(
            f"Batch creation completed | duration: {duration:.3f}s | "
            f"success: {created_count} | duplicate: {duplicate_count} | failed: {failed_count}"
        )

        return results

    def add_bisect_task(self, task_data, priority: int = None):
        """Add a new bisect task to the database with an optional priority."""
        start_time = time.time()

        logger.debug(f"API submission started | Data: {task_data}")

        # Validate task data first
        try:
            validation_start = time.time()
            validated_data = validate_task_data(task_data)
            logger.debug(f"Validation time: {time.time() - validation_start:.3f}s")

            # Extract bad_job_id for duplicate checking
            bad_job_id = validated_data["bad_job_id"]

            if validated_data.get("error_id"):
                error_id = validated_data["error_id"]
                query = {
                    "bool": {
                        "must": [
                            {"equals": {"error_id": error_id}}
                        ]
                    }
                }
                task_identifier = f"error_id='{error_id}'"

            else:
                bisect_metric = validated_data["bisect_metric"]
                query = {
                    "bool": {
                        "must": [
                            {"equals": {"bisect_metric": bisect_metric}},
                            {"equals": {"bad_job_id": bad_job_id}}
                        ]
                    }
                }
                task_identifier = f"bisect_metric='{bisect_metric}'"

            existing = self.client.search(index="bisect", query=query, limit=1)

            if existing and len(existing) > 0:
                logger.info(f"Task already exists | bad_job_id: {bad_job_id}, {task_identifier}")
                logger.debug(f"Total time: {time.time() - start_time:.3f}s (Task exists)")
                return {'status': 'duplicate', 'message': 'Task already exists'}

            task_id = _generate_task_id(
                validated_data["bad_job_id"],
                task_identifier
            )
            task_doc = _create_task_document(validated_data)
            
            # Set priority level if provided
            if priority is not None:
                task_doc["priority_level"] = priority
            
            # Get full_text_kv for classification regardless of git_url
            full_text_kv = ""
            try:
                bad_job_id = validated_data["bad_job_id"]
                logger.debug(f"DEBUG - querying jobs table for full_text_kv classification | bad_job_id: {bad_job_id}")
                
                # Use SQL to query jobs table - simplified query, avoid complex field names
                jobs_sql = f"""
                    SELECT id, full_text_kv
                    FROM jobs 
                    WHERE id = {int(bad_job_id)}
                    LIMIT 1
                """
                
                jobs_results = self.client.sql_select(jobs_sql)
                
                if jobs_results and len(jobs_results) > 0:
                    job_data = jobs_results[0]
                    full_text_kv = job_data.get("full_text_kv", "")
                    logger.debug(f"DEBUG - got full_text_kv for classification: {full_text_kv[:100]}...")
                else:
                    logger.warning(f"bad_job_id not found in jobs table: {bad_job_id}")
            except Exception as e:
                logger.error(f"Error querying jobs table for full_text_kv: {str(e)}")
            
            # Process git_url
            if "git_url" in task_data and task_data["git_url"]:
                task_doc["git_url"] = task_data["git_url"]
                logger.debug(f"DEBUG - adding git_url: {task_data['git_url']}")
            else:
                # If no git_url provided, try extracting from full_text_kv
                if full_text_kv:
                    extracted_url = extract_git_url_from_full_text_kv(full_text_kv)
                    if extracted_url:
                        task_doc["git_url"] = extracted_url
                        logger.debug(f"DEBUG - extracted git_url from full_text_kv | job_id={bad_job_id}, url={extracted_url}")
                    else:
                        logger.warning(f"git_url not found | job_id={bad_job_id}")
                
                if "git_url" not in task_doc:
                    logger.warning("Task data missing git_url and unable to extract from jobs table")
                    task_doc["git_url"] = ""  # Ensure default value
            
            # Auto classify task
            category = categorize_bisect_task(validated_data, full_text_kv)
            task_doc["category"] = category
            logger.debug(f"DEBUG - auto classify task: {category} | bisect_metric: {bool(validated_data.get('bisect_metric'))} | full_text_kv_sample: {full_text_kv[:100]}...")
        
            for key, value in task_doc.items():
                if value is None:
                    if key in ['submit_time', 'updated_at', 'start_time', 'end_time']:
                        task_doc[key] = 0
                    else:
                        task_doc[key] = ''
                    logger.debug(f"Cleaning null field during task creation: {key} = {task_doc[key]}")
        
            logger.debug(f"DEBUG - Preparing to insert task | ID: {task_id}, Document: {task_doc}")
            
            result = self.client.insert("bisect", task_id, task_doc)
            
            logger.debug(f"DEBUG - insert result | ID: {task_id}, success: {result}")

            if result:
                return {'status': 'created', 'message': 'Task created successfully', 'task_id': task_id}
            else:
                return {'status': 'failed', 'message': 'Failed to insert task'}
        except Exception as e:
            logger.error(f"Failed to add task: {str(e)}")
            logger.error(f"Stack trace:\n{traceback.format_exc()}")
            return {'status': 'error', 'message': f'Exception: {str(e)}'}

    def _run_producer_once(self, force: bool = False):
        """Execute a complete producer task discovery cycle (Error + Performance)"""
        logger.info(f"========== BisectProducer cycle STARTED (force={force}) ==========")

        # 1. Execute error type producer
        error_success_count = 0
        try:
            error_producer = ErrorBisectProducer(self.client, self._config)
            error_producer.add_bisect_task_func = self.add_bisect_task
            error_success_count = error_producer.execute_producer_cycle(force_run_scripts=force)
            logger.info(f"[Error Producer] completed | new_tasks: {error_success_count}")
        except Exception as e:
            logger.error(f"[Error Producer] failed: {e}")
            logger.error(traceback.format_exc())

        # 2. Execute performance type producer
        perf_success_count = 0
        try:
            perf_producer = PerformanceBisectProducer(self.client, self._config)
            perf_success_count = perf_producer.execute_producer_cycle()
            logger.info(f"[Performance Producer] completed | new_tasks: {perf_success_count}")
        except Exception as e:
            logger.error(f"[Performance Producer] failed: {e}")
            logger.error(traceback.format_exc())

        # Clear cache
        if len(self.processed_jobs_cache) > 5000:
            logger.info(f"Cache size ({len(self.processed_jobs_cache)}) exceeds limit, cleaning...")
            cache_list = list(self.processed_jobs_cache)
            keep_size = min(2500, len(cache_list) // 2)
            self.processed_jobs_cache = set(cache_list[-keep_size:])
            logger.info(f"Cache cleaned, kept {len(self.processed_jobs_cache)} recent entries")

        total_tasks = error_success_count + perf_success_count
        logger.info(f"========== BisectProducer cycle COMPLETED | total_tasks: {total_tasks} (Error: {error_success_count}, Perf: {perf_success_count}) ==========")

    def trigger_producer_run(self, force: bool = False):
        """API endpoint to manually trigger a producer run."""
        # Try to acquire lock to ensure only one producer runs at a time
        if self.producer_lock.acquire(blocking=False):
            try:
                logger.info(f"Producer run triggered manually via API (force={force}).")
                
                # Define a wrapper to release the lock after execution
                def producer_wrapper(force_flag):
                    try:
                        self._run_producer_once(force=force_flag)
                    finally:
                        if self.producer_lock.locked():
                            self.producer_lock.release()
                            logger.info("Manual producer run finished, lock released.")

                # Use a dedicated thread instead of the shared thread pool
                # This prevents the producer from being blocked by a busy worker pool
                producer_thread = threading.Thread(
                    target=producer_wrapper,
                    args=(force,),
                    name="ManualProducerRunner",
                    daemon=True
                )
                producer_thread.start()
                
                return {'status': 'success', 'message': 'Producer run started in the background.'}
            except Exception as e:
                # If thread start fails, ensure lock is released
                self.producer_lock.release()
                logger.error(f"Failed to start producer thread: {e}")
                return {'status': 'error', 'message': str(e)}
        else:
            logger.warning("Manual producer run requested, but it is already running.")
            return {'status': 'busy', 'message': 'Producer is already running.'}

    def _start_background_tasks(self):
        """Start background tasks - optimized version"""
        background_threads = []

        # 1. Always start consumer thread
        logger.info("Starting BisectConsumer thread...")
        consumer_thread = threading.Thread(
            target=self.bisect_consumer,
            daemon=True,
            name="BisectConsumer"
        )
        consumer_thread.start()
        background_threads.append(("BisectConsumer", consumer_thread))
        logger.info(f"BisectConsumer thread started with ID: {consumer_thread.ident}")

        # 3. Repository periodic cleanup thread
        repo_cleanup_thread = threading.Thread(
            target=self._repo_cleanup_worker,
            daemon=True,
            name="RepoCleanupWorker"
        )
        repo_cleanup_thread.start()
        background_threads.append(("RepoCleanupWorker", repo_cleanup_thread))

        # 4. Producer thread (start based on config)
        # Unified BisectProducer thread, includes both Error and Performance types
        if Config.BISECT_PRODUCER_ENABLED:
            producer_thread = threading.Thread(
                target=self.bisect_producer,
                daemon=True,
                name="BisectProducer"
            )
            producer_thread.start()
            background_threads.append(("BisectProducer", producer_thread))
            logger.info("BisectProducer started (Error + Performance)")
        else:
            logger.info("Producer background tasks disabled (by config)")


        # 6. SuccessTaskValidator thread (handles both success and verifying tasks)
        logger.info("Starting SuccessTaskValidator thread...")
        success_validator_thread = threading.Thread(
            target=self.success_task_validator_consumer,
            daemon=True,
            name="SuccessTaskValidator"
        )
        success_validator_thread.start()
        background_threads.append(("SuccessTaskValidator", success_validator_thread))
        logger.info(f"SuccessTaskValidator thread started with ID: {success_validator_thread.ident}")

        # 7. HEAD regression detection thread (temporarily disabled)
        # logger.info("Starting HeadValidator thread...")
        # head_validator_thread = threading.Thread(
        #     target=self.head_validator_consumer,
        #     daemon=True,
        #     name="HeadValidator"
        # )
        # head_validator_thread.start()
        # background_threads.append(("HeadValidator", head_validator_thread))
        # logger.info(f"HeadValidator thread started with ID: {head_validator_thread.ident}")
        logger.info("HeadValidator disabled (temporarily)")

        # 7. Record started threads
        for name, thread in background_threads:
            logger.info(f"Background task started: {name} (Thread ID: {thread.ident})")

        logger.info(f"Total background threads started: {len(background_threads)}")

        # 6. Store thread references for management
        self.background_threads = background_threads

    def _repo_cleanup_worker(self):
        """Periodically clean up old or residual repository directories"""
        while self.running:
            try:
                logger.info("Running periodic repository cleanup...")
                self._clean_old_repos(max_age_days=14) # Clean repos older than 14 days
            except Exception as e:
                logger.error(f"Error during periodic repo cleanup: {e}")
            
            # Sleep for 6 hours
            time.sleep(6 * 3600)


    def bisect_producer(self):
        """Unified Bisect task producer - includes both Error and Performance types"""
        if not Config.BISECT_PRODUCER_ENABLED:
            logger.info("BisectProducer is disabled by config, exiting.")
            return

        if Config.BISECT_PRODUCER_SCHEDULED_ENABLED:
            # Scheduled execution mode
            try:
                hour, minute = map(int, Config.BISECT_PRODUCER_SCHEDULED_TIME.split(':'))
            except ValueError:
                logger.error(f"Invalid BISECT_PRODUCER_SCHEDULED_TIME format '{Config.BISECT_PRODUCER_SCHEDULED_TIME}'. Use HH:MM. Disabling producer.")
                return

            logger.info(f"Producer is in scheduled mode. Will run daily at {hour:02d}:{minute:02d}.")

            while self.running:
                now = datetime.now()
                next_run_time = now.replace(hour=hour, minute=minute, second=0, microsecond=0)

                if now > next_run_time:
                    # If today's time has passed, schedule for tomorrow
                    next_run_time += timedelta(days=1)

                wait_seconds = (next_run_time - now).total_seconds()
                logger.info(f"Producer will run next at {next_run_time}. Waiting for {wait_seconds / 3600:.2f} hours.")

                # Sleep in 60s intervals to respond to exit signal promptly
                sleep_end_time = time.time() + wait_seconds
                while self.running and time.time() < sleep_end_time:
                    time.sleep(60)

                if not self.running:
                    break

                # Execute producer logic
                with self.producer_lock:
                    self._run_producer_once()
        else:
            # Interval execution mode (original logic)
            logger.info(f"Producer is in interval mode. Will run every {Config.BISECT_PRODUCER_CYCLE_HOURS} hours.")
            while self.running:
                with self.producer_lock:
                    self._run_producer_once()

                # Sleep for configured interval
                logger.info(f"Producer finished a cycle, sleeping for {self.producer_interval / 3600:.1f} hours.")
                time.sleep(self.producer_interval)

    def bisect_consumer(self):
        """Consumer: process waiting bisect tasks with locking mechanism and exponential backoff"""

        # Add debug info
        current_thread = threading.current_thread()
        logger.info(f"BisectConsumer started in thread {current_thread.name}")

        consumer = BisectConsumer(self.client, self._config)
        consumer.repo_manager = self.repo_manager

        logger.info("BisectConsumer initialized, starting main loop...")

        # Clean up stale locks immediately on startup
        logger.info("Performing initial stale lock cleanup...")
        self._cleanup_stale_locks()

        # Exponential backoff variables
        consecutive_empty_rounds = 0
        last_lock_cleanup_time = time.time()
        LOCK_CLEANUP_INTERVAL = 60  # Clean up locks every 1 min (prevent lock leaks)

        while self.running:
            start_time = time.time()
            logger.debug(f"Consumer cycle starting... running={self.running}")

            # Periodically clean up stale locks (prevent lock leaks)
            if start_time - last_lock_cleanup_time > LOCK_CLEANUP_INTERVAL:
                self._cleanup_stale_locks()
                last_lock_cleanup_time = start_time

            try:
                # Dynamically adjust query limit: based on thread pool size
                worker_count = self.thread_pool._max_workers
                # Query batch: fetch more candidates (considering clustering, filtering, locking)
                candidate_batch_size = min(worker_count * 10, 1000)
                # Submit batch: should roughly match thread count, avoid over-submission
                submit_batch_size = worker_count

                logger.info(f"query_batch: {candidate_batch_size}, submit_batch: {submit_batch_size}, workers: {worker_count}")
                logger.debug(f"Active task locks count: {len(self.active_task_locks)}")

                # Fetch a larger batch of candidate tasks for client-side filtering
                sql_query = f"""
                    SELECT id, bad_job_id, error_id, bisect_metric, bisect_status, git_url,
                           submit_time, updated_at, category, priority_level, j
                    FROM bisect
                    WHERE bisect_status = 'wait'
                    ORDER BY priority_level DESC, submit_time DESC
                    LIMIT {candidate_batch_size}
                """

                all_candidates = self.client.sql_select(sql_query)

                if not all_candidates:
                    consecutive_empty_rounds += 1
                    # Exponential backoff: 30s -> 60s -> 120s -> 240s -> max 300s (5 min)
                    backoff_time = min(30 * (2 ** consecutive_empty_rounds), 300)
                    logger.debug(f"No pending tasks, backing off {backoff_time}s (round {consecutive_empty_rounds})")
                    time.sleep(backoff_time)
                    continue

                # Reset backoff counter (found tasks)
                consecutive_empty_rounds = 0

                logger.info(f"Found {len(all_candidates)} candidate tasks from database")

                # Filter out globally locked tasks (by task_id)
                with self.active_task_locks_lock:
                    locked_tasks_set = set(self.active_task_locks)

                unlocked_candidates = [
                    task for task in all_candidates
                    if str(task.get('id')) not in locked_tasks_set
                ]

                logger.info(f"After filtering locked tasks: {len(unlocked_candidates)} unlocked candidates (locked: {len(locked_tasks_set)} task_ids)")

                # Execute clustering, select representative tasks (only as dedup selection, no task relationships)
                tasks_to_submit = self._cluster_and_select_tasks(
                    unlocked_candidates,
                    submit_batch_size
                )

                logger.info(f"Selected {len(tasks_to_submit)} tasks for submission")

                if not tasks_to_submit:
                    # When candidates exist but all locked, wait briefly
                    logger.info("No tasks available for submission after filtering")
                    time.sleep(15)
                    continue

                # Lock and submit the selected tasks
                submitted_count = 0
                skipped_count = 0

                # Step 1: quickly collect tasks to submit while holding lock (avoid deadlock from thread_pool.submit inside lock)
                tasks_ready_to_submit = []
                with self.active_task_locks_lock:
                    logger.info(f"Preparing to submit tasks | locked: {len(self.active_task_locks)} | thread_pool: _max_workers={self.thread_pool._max_workers}, _threads={len(self.thread_pool._threads)}")
                    for task in tasks_to_submit:
                        # Backpressure: Check if we have capacity
                        if not self.task_semaphore.acquire(blocking=False):
                            logger.warning("Task queue full (Backpressure engaged), stopping this round of submissions")
                            break

                        task_id = str(task.get('id'))
                        # Double-check lock, as another cycle might have just locked it
                        if task_id not in self.active_task_locks:
                            self.active_task_locks.add(task_id)
                            tasks_ready_to_submit.append((task_id, task))
                        else:
                            # Release semaphore if we didn't use it
                            self.task_semaphore.release()
                            logger.warning(f"Task already locked, skipping | task_id: {task_id}")
                            skipped_count += 1

                # Step 2: submit tasks to thread pool outside lock (avoid deadlock: workers need same lock on completion)
                for task_id, task in tasks_ready_to_submit:
                    try:
                        future = self.thread_pool.submit(self._process_task_async, consumer, task)
                        logger.info(f"Task submitted to thread pool | task_id: {task_id} | future: {future}")
                        submitted_count += 1
                    except Exception as e:
                        logger.error(f"Task submission failed, rolling back | task_id: {task_id} | error: {e}")
                        # Rollback: remove lock and release semaphore
                        with self.active_task_locks_lock:
                            if task_id in self.active_task_locks:
                                self.active_task_locks.remove(task_id)
                        self.task_semaphore.release()

                if submitted_count > 0:
                    logger.info(f"Consumer cycle completed: submitted {submitted_count} tasks, skipped {skipped_count} | thread_pool: {worker_count} workers")

            except Exception as e:
                logger.error(f"Consumer error: {str(e)}")
                logger.error(traceback.format_exc())
                # Trigger backoff on error too
                consecutive_empty_rounds += 1
            finally:
                # Brief wait when processing tasks, backoff handled above when no tasks
                if 'submitted_count' in locals() and submitted_count > 0:
                    cycle_time = time.time() - start_time
                    sleep_time = max(20, 30 - cycle_time)  # Min 20s wait when processing tasks
                    logger.debug(f"Processed {submitted_count} tasks in {cycle_time:.2f}s, waiting {sleep_time}s")
                    time.sleep(sleep_time)
                else:
                    # If no tasks submitted and not in exponential backoff, wait briefly
                    if consecutive_empty_rounds == 0:
                        cycle_time = time.time() - start_time
                        sleep_time = max(30, 60 - cycle_time)
                        logger.debug(f"Consumer cycle completed in {cycle_time:.2f}s, sleeping for {sleep_time:.2f}s")
                        time.sleep(sleep_time)

        logger.info("BisectConsumer main loop exited")

    def success_task_validator_consumer(self):
        """
        SuccessTaskValidator: verification flow for verifying tasks

        Two main functions:
        1. Check submitted verification job results
        2. Scan new verifying tasks and submit verification jobs
        """
        current_thread = threading.current_thread()
        logger.info(f"SuccessTaskValidator started in thread {current_thread.name}")
        logger.info("Processing verifying tasks: submit verification jobs + check results")

        # Create validator instance
        try:
            validator = SuccessTaskValidator(self.client, self._config)
            logger.info("SuccessTaskValidator initialized successfully")
        except Exception as e:
            logger.error(f"SuccessTaskValidator initialization failed: {str(e)}")
            logger.error(traceback.format_exc())
            return

        # Validation interval
        validation_interval = self._config.get('validation_interval', 60)
        consecutive_empty_rounds = 0

        logger.info(f"SuccessTaskValidator entering main loop | validation_interval: {validation_interval}s | running: {self.running}")

        while self.running:
            start_time = time.time()
            logger.debug(f"SuccessTaskValidator cycle starting... running={self.running}")

            try:
                # Step 1: check submitted verification job results
                try:
                    result = validator.check_verification_results_once(self.repo_manager)
                    if result['checked'] > 0:
                        logger.info(
                            f"Verification result check | checked: {result['checked']} | "
                            f"completed: {result['completed']} | failed: {result['failed']} | "
                            f"timeout: {result['timeout']} | waiting: {result['waiting']} | "
                            f"skipped: {result['skipped']}"
                        )
                except Exception as e:
                    logger.error(f"Failed to check verification results: {str(e)}")
                    logger.error(traceback.format_exc())

                # Step 2: scan new verifying tasks and submit verification jobs
                batch_size = self._config.get('verification_batch_size', 200)
                tasks = validator.scan_unverified_tasks(limit=batch_size)

                if not tasks:
                    consecutive_empty_rounds += 1
                    backoff_time = min(validation_interval * (1 + consecutive_empty_rounds * 0.5), 300)
                    logger.debug(
                        f"No pending verification tasks, backing off {backoff_time:.0f}s "
                        f"(round {consecutive_empty_rounds})"
                    )
                    time.sleep(backoff_time)
                    continue

                # Reset backoff counter
                consecutive_empty_rounds = 0

                # Count task types
                verifying_count = sum(1 for t in tasks if t.get('bisect_status') == 'verifying')
                logger.info(
                    f"Scanned {len(tasks)} pending verification tasks | verifying: {verifying_count}"
                )

                # Group tasks by repository (call validator method)
                tasks_by_repo = validator.group_tasks_by_repo(tasks)

                logger.info(
                    f"Task grouping completed | {len(tasks_by_repo)} repos | "
                    f"total_tasks: {len(tasks)}"
                )

                # Batch submit verification jobs (by repo, call validator method)
                submitted_count = 0
                failed_count = 0

                logger.info(f"Starting to process {len(tasks_by_repo)} repos for verification jobs...")

                for idx, (git_url, repo_tasks) in enumerate(tasks_by_repo.items()):
                    if not self.running:
                        logger.info("SuccessTaskValidator received stop signal, exiting loop")
                        break

                    logger.info(
                        f"Processing repo [{idx+1}/{len(tasks_by_repo)}] | "
                        f"repo: {git_url[:60]}... | tasks: {len(repo_tasks)}"
                    )

                    try:
                        # Batch submit all tasks for this repo (call validator method)
                        logger.debug(f"Calling batch_submit_verification_jobs...")
                        result = validator.batch_submit_verification_jobs(
                            repo_tasks, git_url, self.repo_manager
                        )
                        logger.debug(f"batch_submit_verification_jobs returned: {result}")

                        submitted_count += result.get('submitted', 0)
                        failed_count += result.get('failed', 0)

                    except Exception as e:
                        logger.error(
                            f"Failed to batch submit verification jobs | repo: {git_url[:60]} | "
                            f"tasks: {len(repo_tasks)} | error: {str(e)}"
                        )
                        logger.error(traceback.format_exc())
                        failed_count += len(repo_tasks)

                logger.info(
                    f"SuccessTaskValidator cycle completed | "
                    f"submitted: {submitted_count} | failed: {failed_count} | "
                    f"repos: {len(tasks_by_repo)}"
                )

                # Brief wait
                cycle_time = time.time() - start_time
                sleep_time = max(5, validation_interval - cycle_time)
                logger.debug(f"Submit cycle completed in {cycle_time:.2f}s, waiting {sleep_time:.2f}s")
                time.sleep(sleep_time)

            except Exception as e:
                logger.error(f"SuccessTaskValidator cycle error: {str(e)}")
                logger.error(traceback.format_exc())
                consecutive_empty_rounds += 1
                backoff_time = min(validation_interval * (1 + consecutive_empty_rounds), 300)
                time.sleep(backoff_time)

        logger.info("SuccessTaskValidator thread exited")

    def _process_task_async(self, consumer, task):
        """Process single task asynchronously, release lock and clean up repo on completion"""
        task_id = str(task.get('id'))
        logger.info(f"_process_task_async started for task_id: {task_id}")
        try:
            result = consumer.process_single_task(task)

            if result.get('status') == 'success':
                logger.info(f"Task completed: {task_id}")
                # Note: regression records are now written by VerificationConsumer after verification success
                # This ensures only high-quality verified results enter the regression table
                # Old direct-write logic removed, see verification_consumer.py:_handle_verification_success

                # Batch process wait tasks with same signature
                try:
                    mark_similar_wait_tasks_for_verification(self.client, self.errid_intelligence, task)
                    mark_introduced_errid_tasks_for_verification(self.client, task)
                except Exception as e:
                    # Does not affect main flow, just log errors
                    logger.error(f"Failed to mark similar wait tasks: {str(e)}")
            else:
                error_msg = result.get('error', 'Unknown error')
                logger.error(f"Task failed: {task_id} - {error_msg}")

        except Exception as e:
            logger.error(f"Async task processing uncaught exception: {str(e)}")
            logger.error(traceback.format_exc())
        finally:
            # Backpressure: Release semaphore to allow new tasks
            try:
                self.task_semaphore.release()
            except Exception as e:
                logger.error(f"Failed to release semaphore: {e}")

            # Release task lock
            if task_id:
                with self.active_task_locks_lock:
                    if task_id in self.active_task_locks:
                        self.active_task_locks.remove(task_id)
                        logger.info(f"Released lock for task_id {task_id}. Remaining locks: {len(self.active_task_locks)}")
                    else:
                        logger.warning(f"Attempted to release lock for task_id {task_id}, but it was not found. Current locks: {len(self.active_task_locks)}")

            # Clean up task working directory
            self._cleanup_task_workspace(task_id)

    def _cleanup_task_workspace(self, task_id):
        """Clean up task working directory (delete on both success and failure)"""
        try:
            task_workspace_dir = os.path.join(self.repo_manager.REPO_BASE_DIR, str(task_id))
            if os.path.exists(task_workspace_dir):
                shutil.rmtree(task_workspace_dir, ignore_errors=True)
                logger.info(f"Cleaned task workspace: {task_workspace_dir}")
            else:
                logger.debug(f"Task workspace already clean: {task_workspace_dir}")
        except Exception as e:
            logger.error(f"Failed to clean task workspace {task_id}: {str(e)}")

    def _cleanup_stale_locks(self):
        """
        Clean up stale locks (tasks completed or externally reset)

        Stale lock criteria:
        1. Task status is terminal (success/failed)
        2. Task status is verifying (entered verification phase)
        3. Task does not exist (deleted)
        4. Task status is wait (externally reset via API, needs re-execution)

        Note:
        - Tasks in processing status are being executed, should not clean up
        - Tasks in wait status with locks indicate external reset, should clean up lock for re-execution
        """
        try:
            with self.active_task_locks_lock:
                if not self.active_task_locks:
                    return

                locked_task_ids = list(self.active_task_locks)
                initial_count = len(locked_task_ids)

            logger.debug(f"cleanup stale locks | start | current_locks: {initial_count}")

            # Batch query task statuses
            if locked_task_ids:
                # Query in batches (avoid overly long IN lists)
                batch_size = 500
                stale_locks = set()

                for i in range(0, len(locked_task_ids), batch_size):
                    batch_ids = locked_task_ids[i:i+batch_size]
                    ids_str = ','.join(batch_ids)

                    query = f"""
                        SELECT id, bisect_status
                        FROM bisect
                        WHERE id IN ({ids_str})
                    """

                    results = self.client.sql_select(query)
                    if results:
                        # Build status mapping
                        status_map = {str(r['id']): r.get('bisect_status') for r in results}

                        # Determine which locks are stale
                        for task_id in batch_ids:
                            status = status_map.get(task_id)

                            # Stale lock conditions:
                            # 1. Task does not exist (None)
                            # 2. Task completed (success/failed)
                            # 3. Task in verification (verifying) - no lock needed
                            # 4. Task reset to wait (externally reset via API, clean lock for re-execution)
                            if status is None:
                                stale_locks.add(task_id)
                                logger.debug(f"cleanup stale locks | task not found | task_id: {task_id}")
                            elif status in ('success', 'failed', 'verifying'):
                                stale_locks.add(task_id)
                                logger.debug(f"cleanup stale locks | task completed | task_id: {task_id} | status: {status}")
                            elif status == 'wait':
                                # Task externally reset to wait via API, clean lock for re-consumption
                                stale_locks.add(task_id)
                                logger.info(f"cleanup stale locks | task reset to wait | task_id: {task_id}")
                            # Tasks in processing status are executing, should not clean

                # Remove stale locks
                if stale_locks:
                    with self.active_task_locks_lock:
                        for task_id in stale_locks:
                            self.active_task_locks.discard(task_id)

                        final_count = len(self.active_task_locks)

                    logger.warning(f"cleanup stale locks | cleaned | count: {len(stale_locks)} | before: {initial_count} | after: {final_count}")
                else:
                    logger.debug(f"cleanup stale locks | no stale | all {initial_count} locks are valid")

        except Exception as e:
            logger.error(f"cleanup stale locks | failed | error: {str(e)}")
            logger.error(traceback.format_exc())

    def _clean_old_repos(self, max_age_days=7):
        """Clean up workspace repos unused for specified days

        Delegated to SharedRepoManager as repository management is its responsibility
        """
        try:
            if hasattr(self, 'repo_manager') and self.repo_manager:
                # Call repo_manager cleanup method (simplified return: deleted, skipped)
                deleted, skipped = self.repo_manager.cleanup_old_workspaces(max_age_days)

                # Output statistics report
                if deleted > 0:
                    logger.info(f"╔══════════════════════════════════════════╗")
                    logger.info(f"║        Repository Cleanup Report             ║")
                    logger.info(f"╠══════════════════════════════════════════╣")
                    logger.info(f"║  Skipped (not expired): {skipped:4} repos            ║")
                    logger.info(f"║  Deleted dirs:         {deleted:4} dirs             ║")
                    logger.info(f"╚══════════════════════════════════════════╝")
            else:
                logger.warning("repo_manager not available, skipping old repo cleanup")
        except Exception as e:
            logger.error(f"Error cleaning up repos: {str(e)}")

    def _cleanup_interrupted_tasks(self):
        """Clean up interrupted tasks"""
        try:
            # 1. Get all processing status tasks
            processing_query = {
                "bool": {
                    "must": [
                        {"equals": {"bisect_status": "processing"}}
                    ]
                }
            }
            
            tasks = self.client.search(
                index="bisect",
                query=processing_query,
                limit=1000  # Set large limit to get all processing tasks
            )
            
            if tasks:
                logger.info(f"Found {len(tasks)} tasks needing cleanup")

                # 2. Batch update status to wait
                for task in tasks:
                    task_id = task.get('id')
                    if task_id:
                        update_doc = {
                            "bisect_status": "wait",
                            "updated_at": int(time.time())
                        }
                        self.client.update("bisect", task_id, update_doc)
                        
                logger.info(f"Reset {len(tasks)} task statuses")

                # 3. Delete data directories
                for task in tasks:
                    result_root = task.get('bisect_result_root')
                    if result_root and os.path.exists(result_root):
                        try:
                            shutil.rmtree(result_root)
                            logger.info(f"Successfully deleted data directory: {result_root}")
                        except Exception as e:
                            logger.error(f"Failed to delete directory {result_root}: {str(e)}")

        except Exception as e:
            logger.error(f"Error during cleanup: {str(e)}")
            logger.error(traceback.format_exc())
        finally:
            logger.info("Resource cleanup completed")

    def _batch_check_existing_tasks(self, job_id: int, task_identifiers: list, task_type: str = "error_id") -> set:
        """Batch check which tasks already exist"""
        if not task_identifiers:
            return set()

        try:
            # Build different queries based on task type
            if task_type == "error_id":
                # Build batch query - error ID type
                must_conditions = [
                    {"equals": {"bad_job_id": str(job_id)}},
                    {"in": {"error_id": task_identifiers}}
                ]
                select_field = "error_id"
            else:
                # bisect_metric type
                must_conditions = [
                    {"equals": {"bad_job_id": str(job_id)}},
                    {"in": {"bisect_metric": task_identifiers}}
                ]
                select_field = "bisect_metric"

            # Query using ManticoreSearch
            query = {
                "bool": {
                    "must": must_conditions
                }
            }

            result = self.client.search(index="bisect", query=query, limit=len(task_identifiers))

            existing_ids = {item.get(select_field) for item in result if item.get(select_field)} if result else set()

            logger.debug(f"Job {job_id}: {len(existing_ids)}/{len(task_identifiers)} {task_type}s already exist")
            return existing_ids

        except Exception as e:
            logger.error(f"Batch check failed: {str(e)}")
            return set()

    def _cluster_and_select_tasks(self, candidates: List[Dict], max_selection: int) -> List[Dict]:
        """
        Cluster candidate tasks and select representatives (only as dedup selection, no task relationships)

        Args:
            candidates: candidate task list
            max_selection: maximum number of representative tasks to select

        Returns:
            selected_tasks: selected representative task list (need bisect execution)

        Note:
            - Clustering only used to avoid duplicate bisect of similar errors
            - Does not establish related_task_id relationships
            - Unselected tasks remain in wait status for next cycle
        """
        if not candidates:
            return []

        try:
            # Import smart filter
            errid_intel = ErridIntelligence()

            # Note: theoretically wait status tasks should not have related_task_id
            # If they do, it's dirty data from container restart, should be cleaned during reset
            # As a fallback: if wait tasks have related_task_id, batch clear them
            dirty_task_ids = []
            for task in candidates:
                j_field = task.get('j') or {}
                if isinstance(j_field, str):
                    try:
                        j_field = json.loads(j_field) if j_field else {}
                    except json.JSONDecodeError:
                        j_field = {}

                if j_field.get('related_task_id') or j_field.get('clustered_by'):
                    dirty_task_ids.append(task.get('id'))

            # Batch clear dirty data
            if dirty_task_ids:
                logger.warning(f"Found {len(dirty_task_ids)} wait tasks with clustering dirty data, starting batch cleanup")
                cleaned_count = 0
                dirty_task_ids_set = set(dirty_task_ids)
                for task_id in dirty_task_ids:
                    if self.client.update("bisect", task_id, {"j": {}}):
                        cleaned_count += 1
                logger.warning(f"Cleanup completed | success: {cleaned_count}/{len(dirty_task_ids)}")

                # Critical: sync update in-memory task j field to avoid stale data in later checks
                for task in candidates:
                    if task.get('id') in dirty_task_ids_set:
                        task['j'] = {}

            # Step 1: group by task type (only use signature clustering for build tasks)
            build_tasks = []
            non_build_tasks = []

            for task in candidates:
                category = task.get('category', 'function')  # Default to function
                if category == 'build':
                    build_tasks.append(task)
                else:
                    # function and benchmark tasks do not use signature clustering
                    non_build_tasks.append(task)

            logger.info(f"Task type grouping: build_tasks {len(build_tasks)} (will cluster), non_build_tasks {len(non_build_tasks)} (no clustering)")

            # Step 2: cluster only build tasks by error signature
            signature_groups = {}  # {signature: [task1, task2, ...]}
            skip_clustering_tasks = []  # Tasks skipping clustering, go to independent bisect

            for task in build_tasks:
                # Check if marked to skip clustering
                j_field = task.get('j') or {}
                if isinstance(j_field, str):
                    try:
                        j_field = json.loads(j_field) if j_field else {}
                    except json.JSONDecodeError:
                        j_field = {}

                if j_field.get('skip_clustering'):
                    # Already marked to skip clustering, treat as independent task
                    skip_clustering_tasks.append(task)
                    continue

                error_id = task.get('error_id', '')
                if not error_id:
                    # Tasks without error_id handled separately
                    signature = 'no_error_id'
                else:
                    signature = errid_intel.extract_coarse_signature(error_id)

                if signature not in signature_groups:
                    signature_groups[signature] = []

                signature_groups[signature].append(task)

            if skip_clustering_tasks:
                logger.info(f"Tasks skipping clustering: {len(skip_clustering_tasks)} (will go to independent bisect)")

            logger.info(f"Build task clustering result: {len(build_tasks) - len(skip_clustering_tasks)} tasks -> {len(signature_groups)} clusters")

            # Step 3: select one representative task from each cluster (no relationships, dedup only)
            selected_tasks = []
            skipped_count = 0  # Skipped tasks count (clusters with existing successful tasks)

            # 3.1 Process build task clusters
            for signature, tasks in signature_groups.items():
                # First check if there is already a successful task with same signature
                successful_task = self._find_successful_task_by_signature(signature)

                if successful_task:
                    # Found successful task, immediately mark as verifying (avoid infinite loop)
                    successful_task_id = successful_task['id']
                    logger.info(f"Cluster {signature}: found successful task {successful_task_id}, "
                               f"immediately marking {len(tasks)} tasks as verifying")

                    # Batch mark as verifying (fallback mechanism, prevent missed marking)
                    current_time = int(time.time())
                    marked_count = 0
                    failed_count = 0
                    for task in tasks:
                        try:
                            task_id = task['id']

                            # Check if marking was attempted before (avoid infinite retry)
                            j_field = task.get('j') or {}
                            if isinstance(j_field, str):
                                try:
                                    j_field = json.loads(j_field) if j_field else {}
                                except json.JSONDecodeError:
                                    j_field = {}

                            marking_attempts = j_field.get('marking_attempts', 0)
                            if marking_attempts >= 3:
                                # Retry limit reached, skip clustering mark, let task go through independent bisect flow
                                logger.warning(f"Cluster marking retry limit reached | task_id: {task_id} | attempted {marking_attempts} times | skipping clustering, going to independent bisect")
                                # Clear clustering fields, add skip_clustering flag, keep wait status
                                skip_doc = {
                                    "updated_at": current_time,
                                    "j": {
                                        "skip_clustering": True,
                                        "skip_reason": "marking_attempts_exceeded",
                                        "error_signature": signature
                                    }
                                }
                                self.client.update("bisect", task_id, skip_doc)
                                skipped_count = stats.get('skipped_clustering', 0) + 1
                                stats['skipped_clustering'] = skipped_count
                                continue

                            doc = {
                                "bisect_status": "verifying",
                                "updated_at": current_time,
                                "j": {
                                    "related_task_id": str(successful_task_id),
                                    "error_signature": signature,
                                    "original_error_id": task.get('error_id', ''),
                                    "marked_by_clustering": True,
                                    "marked_timestamp": current_time,
                                    "marking_attempts": marking_attempts + 1
                                }
                            }
                            if self.client.update("bisect", task_id, doc):
                                marked_count += 1
                            else:
                                failed_count += 1
                                logger.warning(f"Cluster marking update failed | task_id: {task_id}")
                        except Exception as e:
                            failed_count += 1
                            logger.error(f"Cluster marking failed | task_id: {task.get('id')} | error: {str(e)}")

                    skipped_count += marked_count
                    if failed_count > 0:
                        logger.warning(f"Cluster marking completed | signature: {signature} | marked: {marked_count}/{len(tasks)} | failed: {failed_count}")
                    else:
                        logger.info(f"Cluster marking completed | signature: {signature} | marked: {marked_count}/{len(tasks)}")

                elif len(tasks) == 1:
                    # No successful task and only single task, select directly
                    selected_tasks.append(tasks[0])
                    logger.debug(f"Cluster {signature}: single task {tasks[0]['id']}")
                else:
                    # No successful task, multiple tasks, select one representative
                    # Sort by priority and submit time, select best representative
                    tasks_sorted = sorted(tasks, key=lambda t: (
                        -t.get('priority_level', 0),  # Higher priority first
                        -t.get('submit_time', 0)      # Later submit time first (negative for descending)
                    ))

                    representative = tasks_sorted[0]
                    selected_tasks.append(representative)

                    logger.info(f"Cluster {signature}: selected task {representative['id']} as representative, "
                               f"remaining {len(tasks)-1} tasks stay in wait status")

            if skipped_count > 0:
                logger.info(f"cluster tasks | marked existing success | count: {skipped_count}")

            # 3.2 Process non-build tasks: add directly to selected_tasks (no clustering)
            if non_build_tasks:
                selected_tasks.extend(non_build_tasks)
                logger.info(f"cluster tasks | non-build tasks | count: {len(non_build_tasks)}")

            # 3.3 Process skip-clustering tasks: add directly to selected_tasks (independent bisect)
            if skip_clustering_tasks:
                selected_tasks.extend(skip_clustering_tasks)
                logger.info(f"cluster tasks | skip-clustering tasks | count: {len(skip_clustering_tasks)}")

            # 3.4 Re-sort by priority (ensure high-priority tasks execute first)
            selected_tasks.sort(key=lambda t: (
                -t.get('priority_level', 0),  # Higher priority first
                -t.get('submit_time', 0)      # Later submit time first
            ))

            # Limit selected task count
            final_selected = selected_tasks[:max_selection]

            logger.info(f"cluster tasks | completed | selected: {len(final_selected)} | "
                       f"marked_existing: {skipped_count}")

            return final_selected

        except Exception as e:
            logger.error(f"Cluster task selection failed: {str(e)}")
            logger.error(traceback.format_exc())
            # Fallback to original logic on failure
            return candidates[:max_selection]

    def _batch_mark_verifying(self, verifying_tasks: List[Dict]):
        """
        Batch mark tasks as verifying status (directly reuse successful tasks)

        Args:
            verifying_tasks: list of tasks to mark, each containing:
                - id: task ID
                - related_task_id: related successful task ID
                - error_signature: error signature
                - original_error_id: original error ID
                - reused_from_successful: True (marked as reuse)
        """
        if not verifying_tasks:
            return

        current_time = int(time.time())
        success_count = 0
        failed_count = 0

        logger.info(f"Starting batch mark of {len(verifying_tasks)} tasks as verifying (reusing successful tasks)")

        for task_info in verifying_tasks:
            try:
                task_id = task_info['id']
                related_task_id = task_info['related_task_id']
                signature = task_info['error_signature']
                original_error_id = task_info.get('original_error_id', '')

                doc = {
                    "bisect_status": "verifying",
                    "updated_at": current_time,
                    "j": {
                        "related_task_id": str(related_task_id),
                        "error_signature": signature,
                        "original_error_id": original_error_id,
                        "clustering_timestamp": current_time,
                        "clustered_by": "task_processor",
                        "reused_from_successful": True,  # Marked as reusing successful task
                        "direct_to_verifying": True  # Skip pending_verification
                    }
                }

                # Update database
                update_result = self.client.update("bisect", task_id, doc)

                if update_result:
                    success_count += 1
                    logger.debug(f"Task {task_id} marked as verifying, linked to successful task {related_task_id}")
                else:
                    failed_count += 1
                    logger.warning(f"Task {task_id} marking failed")

            except Exception as e:
                failed_count += 1
                logger.error(f"Failed to mark task {task_info.get('id', 'unknown')}: {str(e)}")

        logger.info(f"Batch marking verifying completed: success {success_count}, failed {failed_count}")

    def _find_successful_task_by_signature(self, signature: str) -> Optional[Dict]:
        """
        Find successful task with same signature (with cache, only returns high-confidence tasks)

        Args:
            signature: error signature

        Returns:
            Successful task info (contains id, first_bad_commit, j, etc.), or None if not found
        """
        try:
            current_time = int(time.time())

            # Check if cache expired
            with self._success_cache_lock:
                if current_time - self._success_cache_last_refresh > self._success_cache_ttl:
                    logger.info("Success task signature cache expired, refreshing...")
                    self._refresh_success_signature_cache()

                # Look up from cache
                if signature in self._success_signature_cache:
                    cached_task = self._success_signature_cache[signature]

                    # Extract confidence info (for logging)
                    j_field = cached_task.get('j', {})
                    if isinstance(j_field, str):
                        import json
                        j_field = json.loads(j_field) if j_field else {}
                    confidence = j_field.get('confidence', 'unknown')

                    logger.info(
                        f"Found successful task from cache | signature: {signature} | "
                        f"task_id: {cached_task['id']} | confidence: {confidence}"
                    )
                    return cached_task

            logger.debug(f"Successful task not found in cache | signature: {signature}")
            return None

        except Exception as e:
            logger.error(f"Failed to find successful task: {str(e)}")
            logger.error(traceback.format_exc())
            return None

    def _refresh_success_signature_cache(self):
        """
        Refresh success task signature cache (batch), only cache high-confidence tasks
        Note: this method must be called while holding _success_cache_lock
        """
        try:
            # Define confidence priority (for filtering and sorting)
            confidence_priority = {'high': 3, 'medium': 2, 'low': 1, '': 0}
            min_confidence = Config.TASK_REUSE_MIN_CONFIDENCE  # Read min confidence from config
            min_priority = confidence_priority.get(min_confidence, 3)  # Default requires high

            # Query recently successful build tasks (only build tasks use signature clustering)
            query = """
                SELECT id, first_bad_commit, updated_at, j, error_id, category
                FROM bisect
                WHERE bisect_status = 'success' AND category = 'build'
                ORDER BY updated_at DESC
                LIMIT 500
            """

            results = self.client.sql_select(query)
            if not results:
                logger.info("No successful build tasks found")
                return

            # Import smart filter
            errid_intel = ErridIntelligence()

            # Batch build signature cache (only keep high-confidence tasks)
            new_cache = {}
            filtered_count = 0  # Count of low-confidence tasks filtered out

            for task in results:
                error_id = task.get('error_id', '')
                if not error_id:
                    continue

                try:
                    # Extract confidence
                    j_field = task.get('j', {})
                    if isinstance(j_field, str):
                        import json
                        j_field = json.loads(j_field) if j_field else {}

                    confidence = j_field.get('confidence', '').lower()
                    task_priority = confidence_priority.get(confidence, 0)

                    # Only cache tasks meeting min confidence
                    if task_priority < min_priority:
                        filtered_count += 1
                        logger.debug(
                            f"Skipping low confidence task | task_id: {task['id']} | "
                            f"confidence: {confidence or 'unknown'} | min_required: {min_confidence}"
                        )
                        continue

                    signature = errid_intel.extract_coarse_signature(error_id)

                    # If cache already has same signature, compare confidence, keep higher
                    if signature in new_cache:
                        cached_task = new_cache[signature]
                        cached_j = cached_task.get('j', {})
                        if isinstance(cached_j, str):
                            cached_j = json.loads(cached_j) if cached_j else {}
                        cached_confidence = cached_j.get('confidence', '').lower()
                        cached_priority = confidence_priority.get(cached_confidence, 0)

                        # Keep higher confidence task, if same keep later update time
                        if task_priority > cached_priority or (
                            task_priority == cached_priority and
                            task.get('updated_at', 0) > cached_task.get('updated_at', 0)
                        ):
                            new_cache[signature] = task
                    else:
                        new_cache[signature] = task

                except Exception as e:
                    logger.warning(f"Failed to extract signature | task_id: {task['id']} | error: {str(e)}")
                    continue

            self._success_signature_cache = new_cache
            self._success_cache_last_refresh = int(time.time())

            logger.info(
                f"Success task signature cache refreshed | "
                f"signatures: {len(new_cache)} | from {len(results)} successful tasks | "
                f"low_confidence_filtered: {filtered_count} | min_confidence: {min_confidence}"
            )

        except Exception as e:
            logger.error(f"Failed to refresh signature cache: {str(e)}")
            logger.error(traceback.format_exc())

    def _batch_reset_tasks_to_wait(self, task_ids: list, reason: str = "unknown"):
        """
        Batch reset tasks to wait status

        Args:
            task_ids: task ID list
            reason: reset reason (for logging)
        """
        if not task_ids:
            return

        current_time = int(time.time())
        success_count = 0
        failed_count = 0

        logger.info(f"Starting batch reset of {len(task_ids)} tasks to wait | reason: {reason}")

        for task_id in task_ids:
            try:
                doc = {
                    "bisect_status": "wait",
                    "updated_at": current_time,
                    "submit_time": current_time,
                    "j": {
                        "reset_reason": reason,
                        "reset_timestamp": current_time,
                        "reset_by": "verification_consumer"
                    }
                }

                # Update database
                update_result = self.client.update("bisect", task_id, doc)

                if update_result:
                    success_count += 1
                    logger.debug(f"Task {task_id} reset to wait | reason: {reason}")
                else:
                    failed_count += 1
                    logger.warning(f"Task {task_id} reset failed")

            except Exception as e:
                failed_count += 1
                logger.error(f"Failed to reset task {task_id}: {str(e)}")

        logger.info(f"Batch reset completed: success {success_count}, failed {failed_count}")


# Global instance for controllers
bisect_task_instance = TaskProcessor()

