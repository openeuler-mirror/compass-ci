import os
import time
import threading
import re
import subprocess
import hashlib
import traceback
import random
import signal
import sys
import shutil
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor, as_completed
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor, as_completed
from datetime import datetime

sys.path.append((os.environ['CCI_SRC']) + '/src/bisect/lib')
from log_config import logger, StructuredLogger
from manticore_simple import ManticoreClient
from bisect_database import BisectDB


sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from py_bisect import GitBisect
class TaskProcessor:
    @staticmethod
    def _init_process_resources(config):
        """Initialize resources for worker processes"""
        global process_client
        process_client = ManticoreClient(
            host=config['manticore_host'],
            port=config['manticore_http_port']
        )

    @staticmethod
    def _generate_task_path(config: dict, task: dict) -> str:
        """进程安全的路径生成""" 
        path = os.path.join(
            'bisect_results',
            re.sub(r'[^\w\-]', '_', task.get('suite', 'unknown_repo'))[:32],
            datetime.now().strftime("%Y-%m-%d"),
            str(task['bad_job_id']),
            hashlib.md5(task['error_id'].encode()).hexdigest()[:8],
            str(task['id'])
        )
        os.makedirs(path, exist_ok=True, mode=0o755)
        return os.path.abspath(path)

    def _register_signal_handlers(self):
        """注册信号处理"""
        signal.signal(signal.SIGINT, self._handle_exit_signal)
        signal.signal(signal.SIGTERM, self._handle_exit_signal)
        logger.info("已注册退出信号处理器")

    def _handle_exit_signal(self, signum, frame):
        """信号处理回调"""
        logger.warning(f"收到终止信号 {signum}，开始清理...")
        self.running = False
        # 关闭进程池
        self.process_pool.shutdown(wait=False)
        self._cleanup_interrupted_tasks()
        sys.exit(1)


    @staticmethod
    def _process_single_task(config: dict, task: dict):
        """静态任务处理方法"""
        try:
            global process_client
            
            task_id = int(task['id'])
            task_result_root = TaskProcessor._generate_task_path(config, task)

            # DEBUG: 打印子进程配置
            logger.debug(f"DEBUG - 子进程配置 | host={config['manticore_host']}, port={config['manticore_port']}")
            
            # DEBUG: 连接测试
            test_query = {"match_all": {}}
            test_result = process_client.search(index='bisect', query=test_query, limit=1)
            logger.debug(f"DEBUG - 连接测试结果 | 索引存在: {bool(test_result)}")

            try:
                query = {
                    "bool": {
                        "must": [
                            {"equals": {"id": int(task_id)}}
                        ]
                    }
                }
                results = process_client.search(index='bisect', query=query, limit=1) 
                if not results[0]["bisect_status"] == "wait":
                    logger.warning(f"跳过无效任务 | ID: {task_id}")
                    return

                # 更新任务状态为处理中
                update_doc = {
                    "bisect_status": "processing",
                    "updated_at": int(time.time())
                }
                
                if process_client.update("bisect", task_id, update_doc):
                    logger.info(f"开始处理任务 | ID: {task_id}")

                # 准备任务数据
                task['bisect_result_root'] = task_result_root
                # 执行 bisect
                logger.info(f"开始处理任务 |  {task}")
                gb = GitBisect()
                result = gb.find_first_bad_commit(task)

                if result:
                    complete_doc = {
                        "bisect_status": "completed",
                        "project": result.get('repo', ''),
                        "git_url": result.get('git_url', ''),
                        "bad_commit": result.get('first_bad_commit', ''),
                        "first_bad_id": result.get('first_bad_id', ''),
                        "first_result_root": result.get('bad_result_root', ''),
                        "work_dir": result.get('work_dir', ''),
                        "start_time": result.get('start_time', 0),
                        "end_time": int(time.time()),
                        "updated_at": int(time.time())
                    }

                    # 使用重试机制更新结果
                    # 确保不包含 id 字段
                    clean_complete_doc = {
                        k: v for k, v in complete_doc.items() 
                        if k != "id"
                    }
                    
                    if not process_client.update("bisect", task_id, clean_complete_doc):
                        logger.error(f"结果更新失败 | ID: {task_id}")
                    else:
                        # 暂时移除回归数据更新
                        logger.info(f"任务完成 | ID: {task_id}")

                else:
                    # 处理失败情况
                    fail_doc = {
                        "bisect_status": "failed",
                        "last_error": "Bisect execution failed",
                        "updated_at": int(time.time())
                    }
                    # 确保不包含 id 字段
                    clean_fail_doc = {
                        k: v for k, v in fail_doc.items() 
                        if k != "id"
                    }
                    process_client.update("bisect", task_id, clean_fail_doc)
                    logger.error(f"任务执行失败 | ID: {task_id}")

            except Exception as e:
                # 异常处理
                error_doc = {
                    "bisect_status": "failed",
                    "last_error": str(e)[:200],  # 限制错误信息长度
                    "updated_at": int(time.time())
                }
                # 确保不包含 id 字段
                clean_error_doc = {
                    k: v for k, v in error_doc.items() 
                    if k != "id"
                }
                process_client.update("bisect", task_id, clean_error_doc)
                logger.error(f"任务异常 | ID: {task_id} | 错误: {str(e)}")
                logger.error(traceback.format_exc())
            
            return {'id': task_id, 'status': 'success'}
        except Exception as e:
            error_msg = f"Task {task_id} failed: {str(e)}"
            logger.error(error_msg)
            return {'id': task_id, 'status': 'failed', 'error': error_msg}

    def __init__(self):
        self._init_databases()
        self.running = True
        self._register_signal_handlers()
        
        # 进程池初始化
        self._config = {
            "manticore_host": os.environ.get('MANTICORE_HOST', 'localhost'),
            "manticore_port": os.environ.get('MANTICORE_PORT', '9306'),
            "manticore_http_port": os.environ.get('MANTICORE_WRITE_PORT', '9308')
        }
        
        self.process_pool = ProcessPoolExecutor(
            max_workers=min(4, os.cpu_count() or 1),
            initializer=self._init_process_resources,
            initargs=(self._config,)
        )
        self.task_futures = []
        
        logger.info(f"初始化进程池 | 工作进程数: {self.process_pool._max_workers}")
        logger.debug(f"进程池配置: {self._config}")

    def _validate_task_data(self, task: dict) -> dict:
        """确保关键字段有效并清除空值"""
        # 确保 j 字段不为 null
        if 'j' in task and task['j'] is None:
            logger.warning(f"清理无效的 j 字段 | 任务ID={task.get('id')}")
            task['j'] = {}  # 设置为空字典
        
        # 确保必要字段存在
        required_fields = ['bad_job_id', 'error_id']
        for field in required_fields:
            if field not in task:
                raise ValueError(f"缺少必要字段: {field}")
        
        return task
        
    def _init_databases(self):
        """Initialize database connections with pooling"""
        config = {
            "host": os.environ.get('MANTICORE_HOST', 'localhost'),
            "port": int(os.environ.get('MANTICORE_PORT', '9306')),
            "write_port": int(os.environ.get('MANTICORE_WRITE_PORT', '9308'))
        }
        
        self.bisect_db = BisectDB(
            host=config['host'],
            port=config['port'],
            database="bisect",
            pool_size=5
        )
        
        self.jobs_db = BisectDB(
            host=config['host'],
            port=config['port'],
            database="jobs",
            pool_size=5
        )
        
        self.regression_db = BisectDB(
            host=config['host'],
            port=config['port'],
            database="regression",
            pool_size=5
        )
        
        self.client = ManticoreClient(
            host=config['host'],
            port=config['write_port']
        )

    def add_bisect_task(self, task_data):
        """Add a new bisect task to the database"""
        required = ["bad_job_id", "error_id"]
        
        logger.debug(f"DEBUG - 添加任务 | 请求数据: {task_data}")
        
        if not all(field in task_data for field in required):
            missing = [f for f in required if f not in task_data]
            logger.error(f"缺少必填字段: {', '.join(missing)}")
            raise ValueError("Missing required fields: bad_job_id, error_id")
        
        try:
            validated_data = self._validate_task_data(task_data)
            
            task_id = self._generate_task_id(
                validated_data["bad_job_id"],
                validated_data["error_id"]
            )
            
            logger.debug(f"DEBUG - 生成任务ID: {task_id}")
            
            task_doc = {
                "bad_job_id": task_data["bad_job_id"],
                "error_id": task_data["error_id"],
                "bisect_status": "wait",
                "created_at": int(time.time())
            }
        
            logger.debug(f"DEBUG - Preparing to insert task | ID: {task_id}, Document: {task_doc}")
            
            result = self.client.insert("bisect", task_id, task_doc)
            
            logger.debug(f"DEBUG - 插入结果 | ID: {task_id}, 成功: {result}")
            
            return result
        except Exception as e:
            logger.error(f"添加任务失败: {str(e)}")
            logger.error(f"异常堆栈:\n{traceback.format_exc()}")
            return False


    def _generate_task_id(self, bad_job_id, error_id):
        """Generate unique 63-bit positive integer ID"""
        timestamp = f"{time.time():.6f}"
        unique_str = f"{bad_job_id}|{error_id}|{timestamp}"
        hash_bytes = hashlib.sha256(unique_str.encode()).digest()
        hash_int = int.from_bytes(hash_bytes[:8], byteorder='big')
        return hash_int & 0x7FFFFFFFFFFFFFFF


    def _start_background_tasks(self):
        """Start producer and consumer threads"""
        threading.Thread(target=self.bisect_producer, daemon=True).start()
        threading.Thread(target=self.bisect_consumer, daemon=True).start()
        logger.info("Background tasks started")


    def bisect_producer(self):
        """Producer: discover new bisect tasks from jobs database"""
        error_count = 0
        while self.running:
            start_time = time.time()
            try:
                # Get whitelist error IDs
                errid_white_list = self.get_errid_white_list()
                
                # Query tasks needing bisect
                sql_failure = """
                    SELECT id, errid as errid
                    FROM jobs
                    WHERE j.errid IS NOT NULL
                    AND (j.program.makepkg._url IS NOT NULL OR j.ss IS NOT NULL)
                    AND MATCH('job_health=abort job_stage=finish')
                    ORDER BY id DESC
                    LIMIT 1000
                """
                result = self.jobs_db.execute_query(sql_failure)
                
                if not result:
                    time.sleep(300)
                    continue
                    
                # Process tasks
                success_count = 0
                for item in result:
                    bad_job_id = str(item["id"])
                    errids = item["errid"].split()
                    
                    # Prioritize whitelist tasks
                    candidates = set(errids) & errid_white_list if errid_white_list else errids
                    
                    for errid in candidates:
                        # Check for existing tasks
                        existing = self.bisect_db.execute_query(
                            f"SELECT id FROM bisect WHERE error_id='{errid}' AND bad_job_id='{bad_job_id}'"
                        )
                        
                        if not existing:
                            task_data = {
                                "bad_job_id": bad_job_id,
                                "error_id": errid,
                                "bisect_status": "wait"
                            }
                            if self.add_bisect_task(task_data):
                                success_count += 1
                
                logger.info(f"Added {success_count}/{len(result)} new tasks")
                error_count = max(0, error_count - 1)
                
            except Exception as e:
                logger.error(f"Producer error: {str(e)}")
                logger.error(traceback.format_exc())
                sleep_time = min(300, 2 ** error_count)
                time.sleep(sleep_time)
                error_count += 1
            else:
                # Control loop frequency
                cycle_time = time.time() - start_time
                sleep_time = max(0, 300 - cycle_time)
                time.sleep(sleep_time)

    def bisect_consumer(self):
        """Consumer: process waiting bisect tasks"""
        while self.running:
            start_time = time.time()
            processed = 0
            try:
                # Get waiting tasks
                tasks = self.bisect_db.execute_query("""
                    SELECT * 
                    FROM bisect
                    WHERE bisect_status = 'wait'
                    ORDER BY id ASC
                    LIMIT 10
                """)
                
                if not tasks:
                    time.sleep(30)
                    continue
                
                # Submit tasks to process pool
                futures = []
                for task in tasks:
                    future = self.process_pool.submit(
                        self._process_single_task,
                        self._config,
                        task
                    )
                    futures.append(future)
                    self.task_futures.append(future)
                    processed += 1
                
                # Wait for task completion
                for future in as_completed(futures, timeout=72000):
                    try:
                        result = future.result()
                        if result['status'] == 'success':
                            logger.info(f"Task completed: {result['id']}")
                        else:
                            logger.error(f"Task failed: {result['id']} - {result['error']}")
                        
                        # Clean up task directory
                        self._clean_task_dir(result['id'])
                        
                    except Exception as e:
                        logger.error(f"Result processing error: {str(e)}")
                
            except Exception as e:
                logger.error(f"Consumer error: {str(e)}")
                logger.error(traceback.format_exc())
            finally:
                # Control loop frequency
                cycle_time = time.time() - start_time
                sleep_time = max(10, 30 - cycle_time)
                time.sleep(sleep_time)

    def _cleanup_interrupted_tasks(self):
        """清理被中断的任务"""
        try:
            # 1. 获取所有 processing 状态的任务
            tasks = self.bisect_db.execute_query(
                """SELECT id, work_dir as result_root 
                FROM bisect 
                WHERE bisect_status = 'processing'"""
            )
            
            if tasks:
                logger.info(f"发现 {len(tasks)} 个需要清理的任务")

                # 2. 更新状态为 wait
                update_sql = """
                    UPDATE bisect
                    SET bisect_status = 'wait'
                    WHERE bisect_status = 'processing'
                """
                self.bisect_db.execute_update(update_sql)
                logger.info(f"已重置 {len(tasks)} 个任务状态")

                # 3. 删除数据目录
                for task in tasks:
                    result_root = task.get('result_root')
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


    def get_errid_white_list(self):
        """Get error ID whitelist"""
        sql = "SELECT errid FROM regression WHERE record_type = 'errid' AND valid = 'true'"
        result = self.regression_db.execute_query(sql)
        return {item['errid'] for item in result} if result else set()

    def _clean_task_dir(self, task_id):
        """Clean up task directory"""
        task_dir = os.path.join("bisect_results", str(task_id))
        if os.path.exists(task_dir):
            try:
                shutil.rmtree(task_dir)
                logger.info(f"Cleaned task directory: {task_dir}")
            except Exception as e:
                logger.error(f"Failed to clean directory {task_dir}: {str(e)}")

# Global instance for controllers
bisect_task_instance = TaskProcessor()
