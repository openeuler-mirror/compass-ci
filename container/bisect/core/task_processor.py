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
        """注册信号处理"""
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
        容器启动时重置卡在中间状态的任务

        重置规则：
        - processing -> wait (容器重启，线程池任务丢失，需要重新执行)
        - verifying -> wait (容器重启，验证作业状态不可靠，需要重新执行)

        注意：
        - 使用直接 UPDATE 语句，避免 SELECT 的 LIMIT 限制问题
        - 会清理文件系统上的残留 workspace 目录
        """
        try:
            logger.info("容器启动：检查并重置卡住的任务...")

            current_time = int(time.time())

            # 直接 UPDATE 所有 processing 状态的任务为 wait（不修改 j 字段，保留 good_commit 等信息）
            processing_update_sql = f"""
                UPDATE bisect
                SET bisect_status = 'wait', updated_at = {current_time}
                WHERE bisect_status = 'processing'
            """
            processing_result = self.client.sql_raw(processing_update_sql)
            processing_reset = processing_result[0].get('total', 0) if processing_result and len(processing_result) > 0 else 0

            # 直接 UPDATE 所有 verifying 状态的任务为 wait（不修改 j 字段，保留验证信息）
            verifying_update_sql = f"""
                UPDATE bisect
                SET bisect_status = 'wait', updated_at = {current_time}
                WHERE bisect_status = 'verifying'
            """
            verifying_result = self.client.sql_raw(verifying_update_sql)
            verifying_reset = verifying_result[0].get('total', 0) if verifying_result and len(verifying_result) > 0 else 0

            # 清理文件系统上所有以数字开头的 workspace 目录（任务残留）
            cleaned_dirs = 0
            if hasattr(self, 'repo_manager') and self.repo_manager:
                try:
                    base_dir = self.repo_manager.REPO_BASE_DIR
                    if os.path.exists(base_dir):
                        for entry in os.listdir(base_dir):
                            # 任务 workspace 目录名是数字（task_id）
                            if entry.isdigit():
                                task_dir = os.path.join(base_dir, entry)
                                if os.path.isdir(task_dir):
                                    shutil.rmtree(task_dir, ignore_errors=True)
                                    cleaned_dirs += 1
                except Exception as e:
                    logger.warning(f"清理残留目录失败: {str(e)}")

            logger.warning(
                f"容器启动重置完成 | "
                f"processing→wait: {processing_reset} | "
                f"verifying→wait: {verifying_reset} | "
                f"清理目录: {cleaned_dirs}"
            )

        except Exception as e:
            logger.error(f"容器启动重置任务失败: {str(e)}")
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

        # Enhanced Error ID Parser 已移除 - 不再使用相似度匹配

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

        # 添加job信息缓存
        self._job_info_cache = {}
        self._job_info_cache_lock = threading.Lock()
        self._job_cache_ttl = 1800  # 30分钟缓存

        # 成功任务缓存已移除 - 不再使用相似度匹配

        # 成功任务签名缓存（用于优化 _find_successful_task_by_signature 高频查询）
        self._success_signature_cache = {}  # {signature: task_info}
        self._success_cache_ttl = 3600  # 1小时缓存
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
        
        # Add execution lock for consumer tasks - 改为task_id锁
        self.active_task_locks = set()  # 存储正在处理的task_id
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
        """批量添加bisect任务 - 优化版本减少查询风暴"""
        if not task_data_list:
            return []

        results = []
        start_time = time.time()

        logger.info(f"开始批量添加 {len(task_data_list)} 个任务")

        # Phase 1: 批量验证所有任务数据
        validated_tasks = []
        for task_data in task_data_list:
            try:
                validated = validate_task_data(task_data)
                if priority is not None:
                    validated['priority'] = priority
                validated_tasks.append(validated)
            except Exception as e:
                logger.error(f"任务验证失败: {str(e)}")
                results.append({'status': 'error', 'message': str(e)})

        if not validated_tasks:
            return results

        # Phase 2: 批量检查重复（一次查询检查所有）
        error_ids = [t.get("error_id") for t in validated_tasks if t.get("error_id")]
        metric_tasks = [(t.get("bisect_metric"), t.get("bad_job_id"))
                       for t in validated_tasks if t.get("bisect_metric")]

        existing_error_ids = set()
        existing_metrics = set()

        # 批量查询已存在的error_ids
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
                    logger.info(f"批量去重: 发现 {len(existing_error_ids)} 个已存在的error_id")
            except Exception as e:
                logger.error(f"批量检查error_ids失败: {str(e)}")

        # 批量查询已存在的metrics
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
                    logger.error(f"检查metric任务失败: {str(e)}")

        # Phase 3: 批量创建不存在的任务
        created_count = 0
        duplicate_count = 0
        failed_count = 0

        for validated in validated_tasks:
            # 检查是否重复
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

            # 生成task_id
            if validated.get("error_id"):
                task_identifier = f"error_id='{validated['error_id']}'"
            else:
                task_identifier = f"bisect_metric='{validated['bisect_metric']}'"

            task_id = _generate_task_id(validated["bad_job_id"], task_identifier)

            # 创建任务文档
            task_doc = _create_task_document(validated)

            # 设置优先级
            if priority is not None:
                task_doc["priority_level"] = priority

            # 处理git_url和分类
            if "git_url" in validated and validated["git_url"]:
                task_doc["git_url"] = validated["git_url"]
            else:
                # 尝试从缓存或full_text_kv获取
                task_doc["git_url"] = ""

            # 自动分类
            category = categorize_bisect_task(validated, validated.get("full_text_kv", ""))
            task_doc["category"] = category

            # 清理null字段
            for key, value in task_doc.items():
                if value is None:
                    if key in ['submit_time', 'updated_at', 'start_time', 'end_time']:
                        task_doc[key] = 0
                    else:
                        task_doc[key] = ''

            # 插入数据库
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
            f"批量创建完成 | 耗时: {duration:.3f}s | "
            f"成功: {created_count} | 重复: {duplicate_count} | 失败: {failed_count}"
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
            
            # 无论是否有git_url，都获取full_text_kv用于分类判断
            full_text_kv = ""
            try:
                bad_job_id = validated_data["bad_job_id"]
                logger.debug(f"DEBUG - 查询jobs表获取full_text_kv用于分类 | bad_job_id: {bad_job_id}")
                
                # 使用SQL查询jobs表 - 简化查询，避免复杂字段名
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
                    logger.debug(f"DEBUG - 获取full_text_kv用于分类: {full_text_kv[:100]}...")
                else:
                    logger.warning(f"在jobs表中未找到bad_job_id: {bad_job_id}")
            except Exception as e:
                logger.error(f"查询jobs表获取full_text_kv时出错: {str(e)}")
            
            # 处理git_url
            if "git_url" in task_data and task_data["git_url"]:
                task_doc["git_url"] = task_data["git_url"]
                logger.debug(f"DEBUG - 添加 git_url: {task_data['git_url']}")
            else:
                # 如果没有提供git_url，尝试从full_text_kv中提取
                if full_text_kv:
                    extracted_url = extract_git_url_from_full_text_kv(full_text_kv)
                    if extracted_url:
                        task_doc["git_url"] = extracted_url
                        logger.debug(f"DEBUG - 从full_text_kv提取 git_url | job_id={bad_job_id}, url={extracted_url}")
                    else:
                        logger.warning(f"未找到 git_url | job_id={bad_job_id}")
                
                if "git_url" not in task_doc:
                    logger.warning("任务数据缺少git_url，且无法从jobs表中提取")
                    task_doc["git_url"] = ""  # 确保有默认值
            
            # 自动分类任务
            category = categorize_bisect_task(validated_data, full_text_kv)
            task_doc["category"] = category
            logger.debug(f"DEBUG - 自动分类任务: {category} | bisect_metric: {bool(validated_data.get('bisect_metric'))} | full_text_kv样例: {full_text_kv[:100]}...")
        
            for key, value in task_doc.items():
                if value is None:
                    if key in ['submit_time', 'updated_at', 'start_time', 'end_time']:
                        task_doc[key] = 0
                    else:
                        task_doc[key] = ''
                    logger.debug(f"清理任务创建时的null字段: {key} = {task_doc[key]}")
        
            logger.debug(f"DEBUG - Preparing to insert task | ID: {task_id}, Document: {task_doc}")
            
            result = self.client.insert("bisect", task_id, task_doc)
            
            logger.debug(f"DEBUG - 插入结果 | ID: {task_id}, 成功: {result}")

            if result:
                return {'status': 'created', 'message': 'Task created successfully', 'task_id': task_id}
            else:
                return {'status': 'failed', 'message': 'Failed to insert task'}
        except Exception as e:
            logger.error(f"添加任务失败: {str(e)}")
            logger.error(f"异常堆栈:\n{traceback.format_exc()}")
            return {'status': 'error', 'message': f'Exception: {str(e)}'}

    def _run_producer_once(self, force: bool = False):
        """执行一次完整的生产者任务发现（Error + Performance）"""
        logger.info(f"========== BisectProducer cycle STARTED (force={force}) ==========")

        # 1. 执行错误类型生产者
        error_success_count = 0
        try:
            error_producer = ErrorBisectProducer(self.client, self._config)
            error_producer.add_bisect_task_func = self.add_bisect_task
            error_success_count = error_producer.execute_producer_cycle(force_run_scripts=force)
            logger.info(f"[Error Producer] 完成 | 新任务: {error_success_count}")
        except Exception as e:
            logger.error(f"[Error Producer] 失败: {e}")
            logger.error(traceback.format_exc())

        # 2. 执行性能类型生产者
        perf_success_count = 0
        try:
            perf_producer = PerformanceBisectProducer(self.client, self._config)
            perf_success_count = perf_producer.execute_producer_cycle()
            logger.info(f"[Performance Producer] 完成 | 新任务: {perf_success_count}")
        except Exception as e:
            logger.error(f"[Performance Producer] 失败: {e}")
            logger.error(traceback.format_exc())

        # 清理缓存
        if len(self.processed_jobs_cache) > 5000:
            logger.info(f"Cache size ({len(self.processed_jobs_cache)}) exceeds limit, cleaning...")
            cache_list = list(self.processed_jobs_cache)
            keep_size = min(2500, len(cache_list) // 2)
            self.processed_jobs_cache = set(cache_list[-keep_size:])
            logger.info(f"Cache cleaned, kept {len(self.processed_jobs_cache)} recent entries")

        total_tasks = error_success_count + perf_success_count
        logger.info(f"========== BisectProducer cycle COMPLETED | 总任务: {total_tasks} (Error: {error_success_count}, Perf: {perf_success_count}) ==========")

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
        """启动后台任务 - 优化版本"""
        background_threads = []

        # 1. 消费者线程始终启动
        logger.info("Starting BisectConsumer thread...")
        consumer_thread = threading.Thread(
            target=self.bisect_consumer,
            daemon=True,
            name="BisectConsumer"
        )
        consumer_thread.start()
        background_threads.append(("BisectConsumer", consumer_thread))
        logger.info(f"BisectConsumer thread started with ID: {consumer_thread.ident}")

        # 3. 仓库定期清理线程
        repo_cleanup_thread = threading.Thread(
            target=self._repo_cleanup_worker,
            daemon=True,
            name="RepoCleanupWorker"
        )
        repo_cleanup_thread.start()
        background_threads.append(("RepoCleanupWorker", repo_cleanup_thread))

        # 4. 生产者线程（根据配置启动）
        # 统一的 BisectProducer 线程，包含 Error 和 Performance 两种类型
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


        # 6. 🔥 SuccessTaskValidator 线程（统一处理 success 和 verifying 任务）
        logger.info("Starting SuccessTaskValidator thread...")
        success_validator_thread = threading.Thread(
            target=self.success_task_validator_consumer,
            daemon=True,
            name="SuccessTaskValidator"
        )
        success_validator_thread.start()
        background_threads.append(("SuccessTaskValidator", success_validator_thread))
        logger.info(f"SuccessTaskValidator thread started with ID: {success_validator_thread.ident}")

        # 7. HEAD回归检测线程（暂时禁用）
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

        # 7. 记录启动的线程
        for name, thread in background_threads:
            logger.info(f"Background task started: {name} (Thread ID: {thread.ident})")

        logger.info(f"Total background threads started: {len(background_threads)}")

        # 6. 存储线程引用供后续管理
        self.background_threads = background_threads

    def _repo_cleanup_worker(self):
        """定期清理旧的或残留的仓库目录"""
        while self.running:
            try:
                logger.info("Running periodic repository cleanup...")
                self._clean_old_repos(max_age_days=14) # Clean repos older than 14 days
            except Exception as e:
                logger.error(f"Error during periodic repo cleanup: {e}")
            
            # Sleep for 6 hours
            time.sleep(6 * 3600)


    def bisect_producer(self):
        """统一的 Bisect 任务生产者 - 包含 Error 和 Performance 两种类型"""
        if not Config.BISECT_PRODUCER_ENABLED:
            logger.info("BisectProducer is disabled by config, exiting.")
            return

        if Config.BISECT_PRODUCER_SCHEDULED_ENABLED:
            # 定时执行模式
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
                    # 如果今天的时间已过，则安排在明天
                    next_run_time += timedelta(days=1)

                wait_seconds = (next_run_time - now).total_seconds()
                logger.info(f"Producer will run next at {next_run_time}. Waiting for {wait_seconds / 3600:.2f} hours.")

                # 以60秒为间隔进行睡眠，以便能及时响应退出信号
                sleep_end_time = time.time() + wait_seconds
                while self.running and time.time() < sleep_end_time:
                    time.sleep(60)

                if not self.running:
                    break

                # 执行生产者逻辑
                with self.producer_lock:
                    self._run_producer_once()
        else:
            # 间隔执行模式（原始逻辑）
            logger.info(f"Producer is in interval mode. Will run every {Config.BISECT_PRODUCER_CYCLE_HOURS} hours.")
            while self.running:
                with self.producer_lock:
                    self._run_producer_once()

                # 按配置的间隔休眠
                logger.info(f"Producer finished a cycle, sleeping for {self.producer_interval / 3600:.1f} hours.")
                time.sleep(self.producer_interval)

    def bisect_consumer(self):
        """Consumer: process waiting bisect tasks with locking mechanism and exponential backoff"""

        # 添加调试信息
        current_thread = threading.current_thread()
        logger.info(f"BisectConsumer started in thread {current_thread.name}")

        consumer = BisectConsumer(self.client, self._config)
        consumer.repo_manager = self.repo_manager

        logger.info("BisectConsumer initialized, starting main loop...")

        # 启动时立即清理一次陈旧的锁
        logger.info("Performing initial stale lock cleanup...")
        self._cleanup_stale_locks()

        # 指数退避变量
        consecutive_empty_rounds = 0
        last_lock_cleanup_time = time.time()
        LOCK_CLEANUP_INTERVAL = 60  # 每1分钟清理一次锁（防止锁泄漏）

        while self.running:
            start_time = time.time()
            logger.debug(f"Consumer cycle starting... running={self.running}")

            # 定期清理陈旧的锁（防止锁泄漏）
            if start_time - last_lock_cleanup_time > LOCK_CLEANUP_INTERVAL:
                self._cleanup_stale_locks()
                last_lock_cleanup_time = start_time

            try:
                # 动态调整查询限制：基于线程池大小
                worker_count = self.thread_pool._max_workers
                # 查询批次：多查询一些候选（考虑聚类、过滤、锁定）
                candidate_batch_size = min(worker_count * 10, 1000)
                # 提交批次：应该和线程数大致一致，避免过度提交
                submit_batch_size = worker_count

                logger.info(f"查询批次: {candidate_batch_size}, 提交批次: {submit_batch_size}, 工作线程: {worker_count}")
                logger.debug(f"当前活跃任务锁数量: {len(self.active_task_locks)}")

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
                    # 指数退避：30s -> 60s -> 120s -> 240s -> 最大300s (5分钟)
                    backoff_time = min(30 * (2 ** consecutive_empty_rounds), 300)
                    logger.debug(f"无待处理任务，退避等待 {backoff_time}s (第{consecutive_empty_rounds}轮)")
                    time.sleep(backoff_time)
                    continue

                # 重置退避计数器（找到任务了）
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

                # 执行聚类，选择代表任务（仅作为去重选择机制，不建立任务关系）
                tasks_to_submit = self._cluster_and_select_tasks(
                    unlocked_candidates,
                    submit_batch_size
                )

                logger.info(f"Selected {len(tasks_to_submit)} tasks for submission")

                if not tasks_to_submit:
                    # 有候选任务但都被锁定时，短暂等待
                    logger.info("No tasks available for submission after filtering")
                    time.sleep(15)
                    continue

                # Lock and submit the selected tasks
                submitted_count = 0
                skipped_count = 0

                # Step 1: 在持有锁时快速收集需要提交的任务（避免在锁内调用thread_pool.submit造成死锁）
                tasks_ready_to_submit = []
                with self.active_task_locks_lock:
                    logger.info(f"准备提交任务 | 当前锁定: {len(self.active_task_locks)} | 线程池: _max_workers={self.thread_pool._max_workers}, _threads={len(self.thread_pool._threads)}")
                    for task in tasks_to_submit:
                        # Backpressure: Check if we have capacity
                        if not self.task_semaphore.acquire(blocking=False):
                            logger.warning("任务队列已满 (Backpressure engaged)，停止本轮提交")
                            break

                        task_id = str(task.get('id'))
                        # Double-check lock, as another cycle might have just locked it
                        if task_id not in self.active_task_locks:
                            self.active_task_locks.add(task_id)
                            tasks_ready_to_submit.append((task_id, task))
                        else:
                            # Release semaphore if we didn't use it
                            self.task_semaphore.release()
                            logger.warning(f"任务已锁定，跳过 | task_id: {task_id}")
                            skipped_count += 1

                # Step 2: 在锁外提交任务到线程池（避免死锁：工作线程完成时也需要获取同一个锁）
                for task_id, task in tasks_ready_to_submit:
                    try:
                        future = self.thread_pool.submit(self._process_task_async, consumer, task)
                        logger.info(f"任务已提交到线程池 | task_id: {task_id} | future: {future}")
                        submitted_count += 1
                    except Exception as e:
                        logger.error(f"提交任务失败，回滚状态 | task_id: {task_id} | error: {e}")
                        # Rollback: remove lock and release semaphore
                        with self.active_task_locks_lock:
                            if task_id in self.active_task_locks:
                                self.active_task_locks.remove(task_id)
                        self.task_semaphore.release()

                if submitted_count > 0:
                    logger.info(f"Consumer cycle完成: 提交 {submitted_count} 个任务，跳过 {skipped_count} 个 | 线程池: {worker_count} workers")

            except Exception as e:
                logger.error(f"Consumer error: {str(e)}")
                logger.error(traceback.format_exc())
                # 出错时也触发退避
                consecutive_empty_rounds += 1
            finally:
                # 有任务处理时短暂等待，无任务时已经在上面处理了退避
                if 'submitted_count' in locals() and submitted_count > 0:
                    cycle_time = time.time() - start_time
                    sleep_time = max(20, 30 - cycle_time)  # 有任务时最少等20s
                    logger.debug(f"处理了{submitted_count}个任务，耗时{cycle_time:.2f}s，等待{sleep_time}s")
                    time.sleep(sleep_time)
                else:
                    # 如果没有提交任务且没有进入指数退避，短暂等待
                    if consecutive_empty_rounds == 0:
                        cycle_time = time.time() - start_time
                        sleep_time = max(30, 60 - cycle_time)
                        logger.debug(f"Consumer cycle completed in {cycle_time:.2f}s, sleeping for {sleep_time:.2f}s")
                        time.sleep(sleep_time)

        logger.info("BisectConsumer main loop exited")

    def success_task_validator_consumer(self):
        """
        SuccessTaskValidator: 处理 verifying 任务的验证流程

        两个主要功能：
        1. 检查已提交的验证作业结果
        2. 扫描新的 verifying 任务并提交验证作业
        """
        current_thread = threading.current_thread()
        logger.info(f"SuccessTaskValidator started in thread {current_thread.name}")
        logger.info("处理 verifying 任务：提交验证作业 + 检查验证结果")

        # 创建验证器实例
        try:
            validator = SuccessTaskValidator(self.client, self._config)
            logger.info("SuccessTaskValidator 初始化成功")
        except Exception as e:
            logger.error(f"SuccessTaskValidator 初始化失败: {str(e)}")
            logger.error(traceback.format_exc())
            return

        # 验证间隔
        validation_interval = self._config.get('validation_interval', 60)
        consecutive_empty_rounds = 0

        logger.info(f"SuccessTaskValidator 进入主循环 | validation_interval: {validation_interval}s | running: {self.running}")

        while self.running:
            start_time = time.time()
            logger.debug(f"SuccessTaskValidator cycle starting... running={self.running}")

            try:
                # 步骤 1: 检查已提交的验证作业结果
                try:
                    result = validator.check_verification_results_once(self.repo_manager)
                    if result['checked'] > 0:
                        logger.info(
                            f"验证结果检查 | checked: {result['checked']} | "
                            f"completed: {result['completed']} | failed: {result['failed']} | "
                            f"timeout: {result['timeout']} | waiting: {result['waiting']} | "
                            f"skipped: {result['skipped']}"
                        )
                except Exception as e:
                    logger.error(f"检查验证结果失败: {str(e)}")
                    logger.error(traceback.format_exc())

                # 步骤 2: 扫描新的 verifying 任务并提交验证作业
                batch_size = self._config.get('verification_batch_size', 200)
                tasks = validator.scan_unverified_tasks(limit=batch_size)

                if not tasks:
                    consecutive_empty_rounds += 1
                    backoff_time = min(validation_interval * (1 + consecutive_empty_rounds * 0.5), 300)
                    logger.debug(
                        f"无待验证任务，退避等待 {backoff_time:.0f}s "
                        f"(第{consecutive_empty_rounds}轮)"
                    )
                    time.sleep(backoff_time)
                    continue

                # 重置退避计数器
                consecutive_empty_rounds = 0

                # 统计任务类型
                verifying_count = sum(1 for t in tasks if t.get('bisect_status') == 'verifying')
                logger.info(
                    f"扫描到 {len(tasks)} 个待验证任务 | verifying: {verifying_count}"
                )

                # 按仓库分组任务（调用 validator 的方法）
                tasks_by_repo = validator.group_tasks_by_repo(tasks)

                logger.info(
                    f"任务分组完成 | {len(tasks_by_repo)} 个仓库 | "
                    f"总任务: {len(tasks)}"
                )

                # 批量提交验证作业（按仓库，调用 validator 的方法）
                submitted_count = 0
                failed_count = 0

                logger.info(f"开始遍历 {len(tasks_by_repo)} 个仓库提交验证作业...")

                for idx, (git_url, repo_tasks) in enumerate(tasks_by_repo.items()):
                    if not self.running:
                        logger.info("SuccessTaskValidator 收到停止信号，退出循环")
                        break

                    logger.info(
                        f"处理仓库 [{idx+1}/{len(tasks_by_repo)}] | "
                        f"repo: {git_url[:60]}... | tasks: {len(repo_tasks)}"
                    )

                    try:
                        # 批量提交该仓库的所有任务（调用 validator 的方法）
                        logger.debug(f"调用 batch_submit_verification_jobs...")
                        result = validator.batch_submit_verification_jobs(
                            repo_tasks, git_url, self.repo_manager
                        )
                        logger.debug(f"batch_submit_verification_jobs 返回: {result}")

                        submitted_count += result.get('submitted', 0)
                        failed_count += result.get('failed', 0)

                    except Exception as e:
                        logger.error(
                            f"批量提交验证作业失败 | repo: {git_url[:60]} | "
                            f"tasks: {len(repo_tasks)} | error: {str(e)}"
                        )
                        logger.error(traceback.format_exc())
                        failed_count += len(repo_tasks)

                logger.info(
                    f"SuccessTaskValidator cycle completed | "
                    f"submitted: {submitted_count} | failed: {failed_count} | "
                    f"repos: {len(tasks_by_repo)}"
                )

                # 短暂等待
                cycle_time = time.time() - start_time
                sleep_time = max(5, validation_interval - cycle_time)
                logger.debug(f"提交循环完成，耗时 {cycle_time:.2f}s，等待 {sleep_time:.2f}s")
                time.sleep(sleep_time)

            except Exception as e:
                logger.error(f"SuccessTaskValidator cycle error: {str(e)}")
                logger.error(traceback.format_exc())
                consecutive_empty_rounds += 1
                backoff_time = min(validation_interval * (1 + consecutive_empty_rounds), 300)
                time.sleep(backoff_time)

        logger.info("SuccessTaskValidator 线程已退出")

    def _process_task_async(self, consumer, task):
        """异步处理单个任务，并在结束后释放锁和清理仓库"""
        task_id = str(task.get('id'))
        logger.info(f"_process_task_async started for task_id: {task_id}")
        try:
            result = consumer.process_single_task(task)

            if result.get('status') == 'success':
                logger.info(f"Task completed: {task_id}")
                # 注意：regression 记录现在由 VerificationConsumer 在验证成功后写入
                # 这样可以确保只有验证通过的高质量结果才会进入 regression 表
                # 旧的直接写入逻辑已移除，参见 verification_consumer.py:_handle_verification_success

                # 新增：批量处理相同签名的 wait 任务
                try:
                    mark_similar_wait_tasks_for_verification(self.client, self.errid_intelligence, task)
                    mark_introduced_errid_tasks_for_verification(self.client, task)
                except Exception as e:
                    # 不影响主流程，记录错误即可
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

            # 释放任务锁
            if task_id:
                with self.active_task_locks_lock:
                    if task_id in self.active_task_locks:
                        self.active_task_locks.remove(task_id)
                        logger.info(f"Released lock for task_id {task_id}. Remaining locks: {len(self.active_task_locks)}")
                    else:
                        logger.warning(f"Attempted to release lock for task_id {task_id}, but it was not found. Current locks: {len(self.active_task_locks)}")

            # 清理任务工作目录
            self._cleanup_task_workspace(task_id)

    def _cleanup_task_workspace(self, task_id):
        """清理任务的工作目录（成功或失败都删除）"""
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
        清理陈旧的锁（任务已完成或被外部重置）

        陈旧锁的判断标准：
        1. 任务状态是终态（success/failed）
        2. 任务状态是 verifying（已进入验证阶段）
        3. 任务不存在（被删除）
        4. 任务状态是 wait（被外部 API 重置，需要重新执行）

        注意：
        - processing 状态的任务正在执行，不应清理
        - wait 状态的任务如果有锁，说明被外部重置了，应该清理锁让其重新执行
        """
        try:
            with self.active_task_locks_lock:
                if not self.active_task_locks:
                    return

                locked_task_ids = list(self.active_task_locks)
                initial_count = len(locked_task_ids)

            logger.info(f"cleanup stale locks | start | current_locks: {initial_count}")

            # 批量查询这些任务的状态
            if locked_task_ids:
                # 分批查询（避免IN列表过长）
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
                        # 构建状态映射
                        status_map = {str(r['id']): r.get('bisect_status') for r in results}

                        # 判断哪些锁是陈旧的
                        for task_id in batch_ids:
                            status = status_map.get(task_id)

                            # 陈旧锁的条件：
                            # 1. 任务不存在（None）
                            # 2. 任务已完成（success/failed）
                            # 3. 任务在验证中（verifying）- 不需要锁了
                            # 4. 任务被重置为 wait（被外部 API 重置，需要清理锁让其重新执行）
                            if status is None:
                                stale_locks.add(task_id)
                                logger.debug(f"cleanup stale locks | task not found | task_id: {task_id}")
                            elif status in ('success', 'failed', 'verifying'):
                                stale_locks.add(task_id)
                                logger.debug(f"cleanup stale locks | task completed | task_id: {task_id} | status: {status}")
                            elif status == 'wait':
                                # 任务被外部 API 重置为 wait，需要清理锁让其重新被消费
                                stale_locks.add(task_id)
                                logger.info(f"cleanup stale locks | task reset to wait | task_id: {task_id}")
                            # processing 状态的任务正在执行，不应清理

                # 移除陈旧的锁
                if stale_locks:
                    with self.active_task_locks_lock:
                        for task_id in stale_locks:
                            self.active_task_locks.discard(task_id)

                        final_count = len(self.active_task_locks)

                    logger.warning(f"cleanup stale locks | cleaned | count: {len(stale_locks)} | before: {initial_count} | after: {final_count}")
                else:
                    logger.info(f"cleanup stale locks | no stale | all {initial_count} locks are valid")

        except Exception as e:
            logger.error(f"cleanup stale locks | failed | error: {str(e)}")
            logger.error(traceback.format_exc())

    def _clean_old_repos(self, max_age_days=7):
        """清理超过指定天数未使用的工作区仓库

        委托给 SharedRepoManager 处理，因为仓库管理是它的职责
        """
        try:
            if hasattr(self, 'repo_manager') and self.repo_manager:
                # 调用 repo_manager 的清理方法 (简化版返回: deleted, skipped)
                deleted, skipped = self.repo_manager.cleanup_old_workspaces(max_age_days)

                # 输出统计报告
                if deleted > 0:
                    logger.info(f"╔══════════════════════════════════════════╗")
                    logger.info(f"║        仓库清理统计报告                   ║")
                    logger.info(f"╠══════════════════════════════════════════╣")
                    logger.info(f"║  跳过（未超期）: {skipped:4} 个任务               ║")
                    logger.info(f"║  已删除目录:     {deleted:4} 个目录               ║")
                    logger.info(f"╚══════════════════════════════════════════╝")
            else:
                logger.warning("repo_manager not available, skipping old repo cleanup")
        except Exception as e:
            logger.error(f"清理仓库时出错: {str(e)}")

    def _cleanup_interrupted_tasks(self):
        """清理被中断的任务"""
        try:
            # 1. 获取所有 processing 状态的任务
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
                limit=1000  # 设置较大的限制以获取所有processing任务
            )
            
            if tasks:
                logger.info(f"发现 {len(tasks)} 个需要清理的任务")

                # 2. 批量更新状态为 wait
                for task in tasks:
                    task_id = task.get('id')
                    if task_id:
                        update_doc = {
                            "bisect_status": "wait",
                            "updated_at": int(time.time())
                        }
                        self.client.update("bisect", task_id, update_doc)
                        
                logger.info(f"已重置 {len(tasks)} 个任务状态")

                # 3. 删除数据目录
                for task in tasks:
                    result_root = task.get('bisect_result_root')
                    if result_root and os.path.exists(result_root):
                        try:
                            shutil.rmtree(result_root)
                            logger.info(f"成功删除数据目录: {result_root}")
                        except Exception as e:
                            logger.error(f"删除目录失败 {result_root}: {str(e)}")

        except Exception as e:
            logger.error(f"清理过程中发生错误: {str(e)}")
            logger.error(traceback.format_exc())
        finally:
            logger.info("资源清理完成")

    def _batch_check_existing_tasks(self, job_id: int, task_identifiers: list, task_type: str = "error_id") -> set:
        """批量检查哪些任务已经存在"""
        if not task_identifiers:
            return set()

        try:
            # 根据任务类型构造不同的查询
            if task_type == "error_id":
                # 构造批量查询 - 错误ID类型
                must_conditions = [
                    {"equals": {"bad_job_id": str(job_id)}},
                    {"in": {"error_id": task_identifiers}}
                ]
                select_field = "error_id"
            else:
                # bisect_metric类型
                must_conditions = [
                    {"equals": {"bad_job_id": str(job_id)}},
                    {"in": {"bisect_metric": task_identifiers}}
                ]
                select_field = "bisect_metric"

            # 使用ManticoreSearch查询
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
            logger.error(f"批量检查失败: {str(e)}")
            return set()

    def _cluster_and_select_tasks(self, candidates: List[Dict], max_selection: int) -> List[Dict]:
        """
        对候选任务进行聚类，选择代表任务（仅作为去重选择机制，不建立任务关系）

        Args:
            candidates: 候选任务列表
            max_selection: 最多选择多少个代表任务

        Returns:
            selected_tasks: 选中的代表任务列表（需要执行 bisect）

        注意：
            - 聚类仅用于避免重复 bisect 相似的错误
            - 不建立 related_task_id 关系
            - 未选中的任务保持 wait 状态，等待下次循环
        """
        if not candidates:
            return []

        try:
            # 导入智能筛选器
            errid_intel = ErridIntelligence()

            # 注意：理论上 wait 状态的任务不应该有 related_task_id
            # 如果有，说明是容器重启后的脏数据，应该在重置时被清除
            # 这里作为兜底处理：如果发现 wait 任务有 related_task_id，批量清除
            dirty_task_ids = []
            for task in candidates:
                j_field = task.get('j') or {}
                if isinstance(j_field, str):
                    try:
                        j_field = json.loads(j_field) if j_field else {}
                    except:
                        j_field = {}

                if j_field.get('related_task_id') or j_field.get('clustered_by'):
                    dirty_task_ids.append(task.get('id'))

            # 批量清除脏数据
            if dirty_task_ids:
                logger.warning(f"发现 {len(dirty_task_ids)} 个 wait 任务有聚类脏数据，开始批量清除")
                cleaned_count = 0
                dirty_task_ids_set = set(dirty_task_ids)
                for task_id in dirty_task_ids:
                    if self.client.update("bisect", task_id, {"j": {}}):
                        cleaned_count += 1
                logger.warning(f"清除完成 | 成功: {cleaned_count}/{len(dirty_task_ids)}")

                # 关键：同步更新内存中 task 对象的 j 字段，避免后续判断使用旧数据
                for task in candidates:
                    if task.get('id') in dirty_task_ids_set:
                        task['j'] = {}

            # 步骤 1: 按任务类型分组（只对构建任务使用签名聚类）
            build_tasks = []
            non_build_tasks = []

            for task in candidates:
                category = task.get('category', 'function')  # 默认为 function
                if category == 'build':
                    build_tasks.append(task)
                else:
                    # function 和 benchmark 任务不使用签名聚类
                    non_build_tasks.append(task)

            logger.info(f"任务类型分组: 构建任务 {len(build_tasks)} 个（将聚类）, 非构建任务 {len(non_build_tasks)} 个（不聚类）")

            # 步骤 2: 只对构建任务按错误签名聚类
            signature_groups = {}  # {signature: [task1, task2, ...]}
            skip_clustering_tasks = []  # 跳过聚类的任务，直接走独立 bisect

            for task in build_tasks:
                # 检查是否已标记跳过聚类
                j_field = task.get('j') or {}
                if isinstance(j_field, str):
                    try:
                        j_field = json.loads(j_field) if j_field else {}
                    except:
                        j_field = {}

                if j_field.get('skip_clustering'):
                    # 已标记跳过聚类，直接作为独立任务
                    skip_clustering_tasks.append(task)
                    continue

                error_id = task.get('error_id', '')
                if not error_id:
                    # 没有 error_id 的任务单独处理
                    signature = 'no_error_id'
                else:
                    signature = errid_intel.extract_coarse_signature(error_id)

                if signature not in signature_groups:
                    signature_groups[signature] = []

                signature_groups[signature].append(task)

            if skip_clustering_tasks:
                logger.info(f"跳过聚类的任务: {len(skip_clustering_tasks)} 个（将走独立 bisect）")

            logger.info(f"构建任务聚类结果: {len(build_tasks) - len(skip_clustering_tasks)} 个任务 → {len(signature_groups)} 个聚类")

            # 步骤 3: 从每个聚类选择一个代表任务（不建立关系，仅作为去重选择）
            selected_tasks = []
            skipped_count = 0  # 跳过的任务数（已有成功任务的聚类）

            # 3.1 处理构建任务的聚类
            for signature, tasks in signature_groups.items():
                # 先查询是否已经有成功的任务具有相同签名
                successful_task = self._find_successful_task_by_signature(signature)

                if successful_task:
                    # 找到已成功的任务，立即标记为 verifying（避免无限循环）
                    successful_task_id = successful_task['id']
                    logger.info(f"聚类 {signature}: 找到已成功任务 {successful_task_id}，"
                               f"立即标记 {len(tasks)} 个任务为 verifying")

                    # 批量标记为 verifying（兜底机制，防止漏标）
                    current_time = int(time.time())
                    marked_count = 0
                    failed_count = 0
                    for task in tasks:
                        try:
                            task_id = task['id']

                            # 检查是否之前已经尝试标记过（避免无限重试）
                            j_field = task.get('j') or {}
                            if isinstance(j_field, str):
                                try:
                                    j_field = json.loads(j_field) if j_field else {}
                                except:
                                    j_field = {}

                            marking_attempts = j_field.get('marking_attempts', 0)
                            if marking_attempts >= 3:
                                # 达到重试上限，跳过聚类标记，让任务走独立 bisect 流程
                                logger.warning(f"聚类标记达到重试上限 | task_id: {task_id} | 已尝试 {marking_attempts} 次 | 跳过聚类，走独立 bisect")
                                # 清除聚类相关字段，添加 skip_clustering 标记，保持 wait 状态
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
                                logger.warning(f"聚类标记更新失败 | task_id: {task_id}")
                        except Exception as e:
                            failed_count += 1
                            logger.error(f"聚类标记失败 | task_id: {task.get('id')} | error: {str(e)}")

                    skipped_count += marked_count
                    if failed_count > 0:
                        logger.warning(f"聚类标记完成 | signature: {signature} | marked: {marked_count}/{len(tasks)} | failed: {failed_count}")
                    else:
                        logger.info(f"聚类标记完成 | signature: {signature} | marked: {marked_count}/{len(tasks)}")

                elif len(tasks) == 1:
                    # 没有成功任务，且只有单个任务，直接选择
                    selected_tasks.append(tasks[0])
                    logger.debug(f"聚类 {signature}: 单个任务 {tasks[0]['id']}")
                else:
                    # 没有成功任务，多个任务，选择一个代表
                    # 按优先级和提交时间排序，选择最佳代表
                    tasks_sorted = sorted(tasks, key=lambda t: (
                        -t.get('priority_level', 0),  # 优先级高的在前
                        -t.get('submit_time', 0)      # 提交时间晚的在前（负号表示降序）
                    ))

                    representative = tasks_sorted[0]
                    selected_tasks.append(representative)

                    logger.info(f"聚类 {signature}: 选择任务 {representative['id']} 作为代表，"
                               f"其余 {len(tasks)-1} 个任务保持 wait 状态")

            if skipped_count > 0:
                logger.info(f"cluster tasks | marked existing success | count: {skipped_count}")

            # 3.2 处理非构建任务：直接添加到 selected_tasks（不聚类）
            if non_build_tasks:
                selected_tasks.extend(non_build_tasks)
                logger.info(f"cluster tasks | non-build tasks | count: {len(non_build_tasks)}")

            # 3.3 处理跳过聚类的任务：直接添加到 selected_tasks（走独立 bisect）
            if skip_clustering_tasks:
                selected_tasks.extend(skip_clustering_tasks)
                logger.info(f"cluster tasks | skip-clustering tasks | count: {len(skip_clustering_tasks)}")

            # 3.4 重新按优先级排序（确保高优先级任务优先执行）
            selected_tasks.sort(key=lambda t: (
                -t.get('priority_level', 0),  # 优先级高的在前
                -t.get('submit_time', 0)      # 提交时间晚的在前
            ))

            # 限制选中的任务数量
            final_selected = selected_tasks[:max_selection]

            logger.info(f"cluster tasks | completed | selected: {len(final_selected)} | "
                       f"marked_existing: {skipped_count}")

            return final_selected

        except Exception as e:
            logger.error(f"聚类选择任务失败: {str(e)}")
            logger.error(traceback.format_exc())
            # 失败时回退到原始逻辑
            return candidates[:max_selection]

    def _batch_mark_verifying(self, verifying_tasks: List[Dict]):
        """
        批量标记任务为 verifying 状态（直接复用已成功任务）

        Args:
            verifying_tasks: 待标记的任务列表，每个元素包含:
                - id: 任务ID
                - related_task_id: 关联的已成功任务ID
                - error_signature: 错误签名
                - original_error_id: 原始错误ID
                - reused_from_successful: True（标记为复用）
        """
        if not verifying_tasks:
            return

        current_time = int(time.time())
        success_count = 0
        failed_count = 0

        logger.info(f"开始批量标记 {len(verifying_tasks)} 个任务为 verifying 状态（复用已成功任务）")

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
                        "reused_from_successful": True,  # 标记为复用已成功任务
                        "direct_to_verifying": True  # 跳过 pending_verification
                    }
                }

                # 更新数据库
                update_result = self.client.update("bisect", task_id, doc)

                if update_result:
                    success_count += 1
                    logger.debug(f"任务 {task_id} 标记为 verifying，关联已成功任务 {related_task_id}")
                else:
                    failed_count += 1
                    logger.warning(f"任务 {task_id} 标记失败")

            except Exception as e:
                failed_count += 1
                logger.error(f"标记任务 {task_info.get('id', 'unknown')} 失败: {str(e)}")

        logger.info(f"批量标记 verifying 完成: 成功 {success_count} 个，失败 {failed_count} 个")

    def _find_successful_task_by_signature(self, signature: str) -> Optional[Dict]:
        """
        查找具有相同签名的已成功任务（带缓存，只返回高置信度任务）

        Args:
            signature: 错误签名

        Returns:
            已成功的任务信息（包含 id, first_bad_commit, j 等），如果没有则返回 None
        """
        try:
            current_time = int(time.time())

            # 检查缓存是否过期
            with self._success_cache_lock:
                if current_time - self._success_cache_last_refresh > self._success_cache_ttl:
                    logger.info("成功任务签名缓存已过期，开始刷新...")
                    self._refresh_success_signature_cache()

                # 从缓存查找
                if signature in self._success_signature_cache:
                    cached_task = self._success_signature_cache[signature]

                    # 提取置信度信息（用于日志）
                    j_field = cached_task.get('j', {})
                    if isinstance(j_field, str):
                        import json
                        j_field = json.loads(j_field) if j_field else {}
                    confidence = j_field.get('confidence', 'unknown')

                    logger.info(
                        f"从缓存找到成功任务 | signature: {signature} | "
                        f"task_id: {cached_task['id']} | confidence: {confidence}"
                    )
                    return cached_task

            logger.debug(f"缓存中未找到成功任务 | signature: {signature}")
            return None

        except Exception as e:
            logger.error(f"查找成功任务失败: {str(e)}")
            logger.error(traceback.format_exc())
            return None

    def _refresh_success_signature_cache(self):
        """
        刷新成功任务签名缓存（批量），只缓存高置信度任务
        注意：此方法必须在持有 _success_cache_lock 的情况下调用
        """
        try:
            # 定义置信度优先级（用于过滤和排序）
            confidence_priority = {'high': 3, 'medium': 2, 'low': 1, '': 0}
            min_confidence = Config.TASK_REUSE_MIN_CONFIDENCE  # 从配置读取最小置信度
            min_priority = confidence_priority.get(min_confidence, 3)  # 默认要求 high

            # 查询最近成功的构建任务（只查询构建任务，因为只有构建任务使用签名聚类）
            query = """
                SELECT id, first_bad_commit, updated_at, j, error_id, category
                FROM bisect
                WHERE bisect_status = 'success' AND category = 'build'
                ORDER BY updated_at DESC
                LIMIT 500
            """

            results = self.client.sql_select(query)
            if not results:
                logger.info("没有找到成功的构建任务")
                return

            # 导入智能筛选器
            errid_intel = ErridIntelligence()

            # 批量构建签名缓存（只保留高置信度任务）
            new_cache = {}
            filtered_count = 0  # 被过滤掉的低置信度任务数

            for task in results:
                error_id = task.get('error_id', '')
                if not error_id:
                    continue

                try:
                    # 提取置信度
                    j_field = task.get('j', {})
                    if isinstance(j_field, str):
                        import json
                        j_field = json.loads(j_field) if j_field else {}

                    confidence = j_field.get('confidence', '').lower()
                    task_priority = confidence_priority.get(confidence, 0)

                    # 只缓存满足最小置信度的任务
                    if task_priority < min_priority:
                        filtered_count += 1
                        logger.debug(
                            f"跳过低置信度任务 | task_id: {task['id']} | "
                            f"confidence: {confidence or 'unknown'} | min_required: {min_confidence}"
                        )
                        continue

                    signature = errid_intel.extract_coarse_signature(error_id)

                    # 如果已有相同签名的缓存，比较置信度，保留更高的
                    if signature in new_cache:
                        cached_task = new_cache[signature]
                        cached_j = cached_task.get('j', {})
                        if isinstance(cached_j, str):
                            cached_j = json.loads(cached_j) if cached_j else {}
                        cached_confidence = cached_j.get('confidence', '').lower()
                        cached_priority = confidence_priority.get(cached_confidence, 0)

                        # 保留置信度更高的任务，如果相同则保留更新时间更晚的
                        if task_priority > cached_priority or (
                            task_priority == cached_priority and
                            task.get('updated_at', 0) > cached_task.get('updated_at', 0)
                        ):
                            new_cache[signature] = task
                    else:
                        new_cache[signature] = task

                except Exception as e:
                    logger.warning(f"提取签名失败 | task_id: {task['id']} | error: {str(e)}")
                    continue

            self._success_signature_cache = new_cache
            self._success_cache_last_refresh = int(time.time())

            logger.info(
                f"成功任务签名缓存已刷新 | "
                f"签名数: {len(new_cache)} | 来自 {len(results)} 个成功任务 | "
                f"过滤掉低置信度: {filtered_count} | min_confidence: {min_confidence}"
            )

        except Exception as e:
            logger.error(f"刷新签名缓存失败: {str(e)}")
            logger.error(traceback.format_exc())

    def _batch_reset_tasks_to_wait(self, task_ids: list, reason: str = "unknown"):
        """
        批量重置任务为 wait 状态

        Args:
            task_ids: 任务ID列表
            reason: 重置原因（用于日志记录）
        """
        if not task_ids:
            return

        current_time = int(time.time())
        success_count = 0
        failed_count = 0

        logger.info(f"开始批量重置 {len(task_ids)} 个任务为 wait 状态 | 原因: {reason}")

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

                # 更新数据库
                update_result = self.client.update("bisect", task_id, doc)

                if update_result:
                    success_count += 1
                    logger.debug(f"任务 {task_id} 重置为 wait | 原因: {reason}")
                else:
                    failed_count += 1
                    logger.warning(f"任务 {task_id} 重置失败")

            except Exception as e:
                failed_count += 1
                logger.error(f"重置任务 {task_id} 失败: {str(e)}")

        logger.info(f"批量重置完成: 成功 {success_count} 个，失败 {failed_count} 个")


# Global instance for controllers
bisect_task_instance = TaskProcessor()

