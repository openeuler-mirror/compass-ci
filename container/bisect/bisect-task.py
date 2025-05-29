#!/usr/bin/env python3
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2025 Huawei Technologies Co., Ltd. All rights reserved.
#   Input: manticore JSON
#
#   functions:
#
#       provide API/new-bisect-task
#           add to bisect_tasks
#       loop:
#           consumer:
#               one task from bisect_tasks
#               fork process, start bisect
#           producer:
#               scan job db
#               add failed task to bisect_tasks
#
import json
import re
import subprocess
import hashlib
from datetime import datetime
import yaml
import os
import sys
import shutil
import time
import traceback
import mysql.connector
import hashlib
import signal
import multiprocessing
import threading
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor, as_completed
from random import randint
from flask import Flask, jsonify, request
from flask.views import MethodView
from httpx import RequestError
from functools import wraps


sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from py_bisect import GitBisect
from log_config import logger
sys.path.append((os.environ['CCI_SRC']) + '/lib')
from bisect_database import BisectDB
from manticore_simple import ManticoreClient


app = Flask(__name__)


def generate_task_id(bad_job_id: str, error_id: str) -> int:
    """
    生成符合 Manticore 要求的 63 位正整数 ID
    算法：SHA256(业务ID+时间戳)[前16位] → 十六进制转十进制 → 掩码保留63位
    
    Args:
        bad_job_id: 故障任务ID
        error_id: 错误标识符
        
    Returns:
        63位正整数 (JavaScript 安全整数范围)
    """
    # 1. 构造唯一字符串
    timestamp = f"{time.time():.6f}"  # 微秒级时间戳
    unique_str = f"{bad_job_id}|{error_id}|{timestamp}"
    
    # 2. 计算 SHA256 哈希
    hash_bytes = hashlib.sha256(unique_str.encode()).digest()
    
    # 3. 取前8字节（64位）并转换为整数
    hash_int = int.from_bytes(hash_bytes[:8], byteorder='big')
    
    # 4. 确保最高位为0，得到63位正整数
    return hash_int & 0x7FFFFFFFFFFFFFFF

class BisectTask:
    @staticmethod
    def _init_process_resources(config):
        """子进程资源初始化"""
        global process_client
        process_client = ManticoreClient(
            host=config['manticore_host'],
            port=9308
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
        self._cleanup_interrupted_tasks()
        sys.exit(1)

    @staticmethod
    def _process_single_task(config: dict, task: dict):
        """静态任务处理方法"""
        try:
            global process_bisect_db, process_client
            
            task_id = int(task['id'])
            task_result_root = BisectTask._generate_task_path(config, task)

            try:
                # 使用 ManticoreClient 的 search 方法检查任务状态
                status_check = process_client.search(
                    table="bisect",
                    query={"match": {"id": task_id, "bisect_status": "wait"}},
                    limit=1
                )

                if not status_check:
                    logger.warning(f"跳过无效任务 | ID: {task_id}")
                    return

                # 更新任务状态为处理中
                task["bisect_status"] = "processing"
                # Convert to Manticore SQL update

                if process_client.update("bisect", task_id, task):
                    logger.info(f"开始处理任务 | ID: {task_id}")

                # 准备任务数据
                task['bisect_result_root'] = task_result_root
                # 执行 bisect
                logger.info(f"开始处理任务 |  {task}")
                gb = GitBisect()
                result = gb.find_first_bad_commit(task)

                if result:
                    # 构造完整结果文档
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
                    if not process_client.update("bisect", task_id, complete_doc):
                        logger.error(f"结果更新失败 | ID: {task_id}")
                    else:
                        # 更新回归数据
                        BisectTask.update_regression(task, result)
                        logger.info(f"任务完成 | ID: {task_id}")

                else:
                    # 处理失败情况
                    fail_doc = {
                        "bisect_status": "failed",
                        "last_error": "Bisect execution failed",
                        "updated_at": int(time.time())
                    }
                    process_client.update("bisect", task_id, fail_doc)
                    logger.error(f"任务执行失败 | ID: {task_id}")

            except Exception as e:
                # 异常处理
                error_doc = {
                    "bisect_status": "failed",
                    "last_error": str(e)[:200],  # 限制错误信息长度
                    "updated_at": int(time.time())
                }
                process_client.update("bisect", task_id, error_doc)
                logger.error(f"任务异常 | ID: {task_id} | 错误: {str(e)}")
                logger.error(traceback.format_exc())
            
            return {'id': task_id, 'status': 'success'}
        except Exception as e:
            error_msg = f"Task {task_id} failed: {str(e)}"
            logger.error(error_msg)
            return {'id': task_id, 'status': 'failed', 'error': error_msg}

    def _cleanup_interrupted_tasks(self):
        """清理被中断的任务"""
        try:
            # 1. 获取所有 processing 状态的任务
            tasks = self.bisect_db.execute_query(
                "SELECT id, work_dir as result_root FROM bisect "
                "WHERE bisect_status = 'processing'"
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

    def __init__(self):
        self.bisect_task = None
        self.running = True  # 运行状态标志
        self.client = ManticoreClient(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=int(os.environ.get('MANTICORE_WRITE_PORT', '9308'))
        )
        self.jobs_db = BisectDB(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=os.environ.get('MANTICORE_PORT', '9306'),
            database="jobs",
            pool_size=2
        )
        logger.info(f"主进程 jobs DB 连接 ID: {id(self.jobs_db)}")

        self.bisect_db = BisectDB(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=os.environ.get('MANTICORE_PORT', '9306'),
            database="bisect",
            pool_size=2
        )
        logger.info(f"主进程 bisect DB 连接 ID: {id(self.bisect_db)}")

        # 主进程数据库连接初始化
        self.regression_db = BisectDB(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=os.environ.get('MANTICORE_PORT', '9306'),
            database="regression",
            pool_size=2
        )
        logger.info(f"主进程 RegressionDB 连接 ID: {id(self.regression_db)}")
        
        self._config = {
            "manticore_host": os.environ.get('MANTICORE_HOST', 'localhost'),
            "manticore_port": os.environ.get('MANTICORE_PORT', '9306'),
        }
        
        self.process_pool = ProcessPoolExecutor(
            max_workers=os.cpu_count(),
            initializer=self._init_process_resources,
            initargs=(self._config,)
        )
        self.task_futures = []
        
        self._register_signal_handlers()  # 注册信号处理器
        
        self._start_monitor()


    def add_bisect_task(self, task):
        """Add a new bisect task (atomic operation version)"""
        required_fields = ["bad_job_id", "error_id"]
        for field in required_fields:
            if field not in task:
                raise ValueError(f"Missing required field: {field}")

        try:
            # 生成基于业务数据的强唯一ID
            task_fingerprint = generate_task_id(
                task["bad_job_id"], 
                task["error_id"]
            ) 
            # 原子插入操作 insert(self, index: str, id: int, document: dict) 
            if self.client.insert(index="bisect", id=task_fingerprint, document=task):
                return True
            else:
                return False
        except Exception as e:
            logger.error(f"Unknown error: {str(e)}")
            return False

    def set_priority_level(self, job_info: dict) -> int:
        """
        """
        WATCH_LISTS = {
            "suite": ["check_abi", "pkgbuild"],       # 监控的测试套件
            "repo": ["linux"],                        # 监控的代码仓库
            "error_id": ["stderr.eid../include/linux/thread_info.h:#:#:error:call_to'__bad_copy_from'declared_with_attribute_error:copy_source_size_is_too_small"]  # 监控的错误ID
            }
              # 优先级权重配置
        PRIORITY_WEIGHTS = {
            "suite": 2,
            "repo": 1,
            "error_id": 3
        }

        priority = 0

        for field, weight in PRIORITY_WEIGHTS.items():
            # 获取任务字段值（确保返回字符串）
            job_value = job_info.get(field, "")  # 默认空字符串

            # 获取监控列表
            watch_list = WATCH_LISTS.get(field, [])

            # 检查值是否在监控列表中
            if job_value in watch_list:
                priority += weight

        return priority

    def bisect_producer(self):
        """Producer function optimized for batch processing and rate limiting"""
        error_count = 0

        while self.running:
            if not self.running:
                logger.info("生产者线程收到停止信号")
                break
            start_time = time.time()
            try:
                # Fetch new tasks with time filtering
                new_bisect_tasks = self.get_new_bisect_task_from_jobs()
                logger.info(f"Found {len(new_bisect_tasks)} candidate tasks")
                success_count = 0
                for task in new_bisect_tasks: 
                    if not self.bisect_db.execute_query(f"""SELECT id FROM bisect WHERE error_id='{task['error_id']}' AND bad_job_id='{task['bad_job_id']}'"""):
                        if self.add_bisect_task(task):
                            success_count += 1
                            logger.info(f"Add {task['error_id']} and {task['bad_job_id']} OK")
                
                error_count = max(0, error_count - 1)  # Reduce error count on success

            except Exception as e:
                # 添加详细错误日志
                logger.error(f"Error in bisect_producer: {str(e)}")
                logger.error(f"Failed task data: {task if 'task' in locals() else 'No task data'}")
                logger.error(traceback.format_exc())  # 打印完整堆栈跟踪
                # 指数退避重试机制
                sleep_time = min(300, 2 ** error_count)
                time.sleep(sleep_time)
                error_count += 1
            else:
                # 正常执行后重置错误计数器
                error_count = 0
                cycle_time = time.time() - start_time
                logger.info(f"Producer cycle completed.")
                # 固定间隔休眠，两个循环之间的间隔永远为300秒，无论每次循环的执行时间为多少
                sleep_time = 300 - cycle_time
                logger.info(f"Sleeping for {sleep_time:.2f} seconds until next cycle")
                time.sleep(sleep_time)

    def bisect_consumer(self):
        """
        Consumer function to fetch bisect tasks from Elasticsearch and process them.
        This function runs in an infinite loop, checking for tasks every 30 seconds.
        Tasks are either submitted to a scheduler or run locally, depending on the environment variable 'bisect_mode'.
        """
        while self.running:
            if not self.running:
                logger.info("消费者线程收到停止信号")
                break
            cycle_start = time.time()
            processed = 0
            try:
                # Fetch bisect tasks from Elasticsearch
                bisect_tasks = self.get_tasks_from_bisect_task()
                if not bisect_tasks:
                    time.sleep(30)
                    continue

                if bisect_tasks:  # If tasks are found
                    # Check the mode of operation from environment variable
                    if os.getenv('bisect_mode') == "submit":
                        # If mode is 'submit', send tasks to the scheduler
                        logger.debug("Submitting bisect tasks to scheduler")
                        self.submit_bisect_tasks(bisect_tasks)
                    else:
                        # If mode is not 'submit', run tasks locally
                        logger.debug("Running bisect tasks locally")
                        # 多线程在这里处理? 
                        # 一次处理一个 error_id 的系列
                        self.run_bisect_tasks(bisect_tasks)
                processed = len(bisect_tasks)

            except Exception as e:
                # Log any errors that occur during task processing
                logger.error(f"Error in bisect_consumer: {e}")
                # 异常后休眠时间加倍（简易熔断机制）
                time.sleep(60)
            finally:
                # 记录处理指标
                cycle_time = time.time() - cycle_start
                logger.info(f"Consumer cycle processed {processed} tasks in {cycle_time:.2f}s")

                # 动态休眠控制（无任务时延长休眠）
                sleep_time = 30 if processed > 0 else 60
                time.sleep(max(10, sleep_time - cycle_time))  # 保证最小间隔
    def run_bisect_tasks(self, bisect_tasks):
        """改造后的任务提交方法"""
        if not bisect_tasks:
            return
        futures = []
        for task in bisect_tasks:
            future = self.process_pool.submit(
                self._process_single_task,
                self._config,
                task
            )
            futures.append(future)
            self.task_futures.append(future)

        for future in as_completed(futures, timeout=72000):  # 2小时超时
            try:
                result = future.result()
                if result['status'] == 'success':
                    logger.info(f"任务完成: {result['id']}")
                else:
                    logger.error(f"任务失败: {result['id']} - {result['error']}")
            except TimeoutError:
                logger.error("任务处理超时，可能发生死锁")
                future.cancel()
            except Exception as e:
                logger.error(f"结果处理异常: {str(e)}")

    def update_regression(self, task, result):
        """使用 ManticoreClient 更新回归数据库"""
        try:
            # 参数校验
            if not task.get('error_id') or not task.get('bad_job_id'):
                logger.error("Invalid task format for regression update")
                return

            # 获取当前时间戳（秒级）
            current_time = int(time.time())
            bad_job_id = task['bad_job_id']
            error_id = task['error_id'].replace("'", "''")  # 转义单引号

            # 检查是否已存在有效记录
            existing = process_client.search(
                table="regression",
                query={
                    "bool": {
                        "must": [
                            {"match": {"record_type": "errid"}},
                            {"match": {"errid": error_id}},
                            {"match": {"valid": "true"}}
                        ]
                    }
                },
                limit=1
            )

            if not existing:
                # 插入新记录
                new_id = int(f"{current_time}{randint(1000,9999)}")  # 生成唯一ID
                category = result.get('category', 'unknown').replace("'", "''")
                related_jobs_json = json.dumps([bad_job_id])  # 初始化为数组

                new_record = {
                    "id": new_id,
                    "record_type": "errid",
                    "errid": error_id,
                    "category": category,
                    "first_seen": current_time,
                    "last_seen": current_time,
                    "bisect_count": 1,
                    "related_jobs": related_jobs_json,
                    "valid": "true"
                }

                if not process_client.insert("regression", new_id, new_record):
                    logger.error(f"插入新记录失败 | ErrorID: {error_id}")
            else:
                # 更新现有记录
                record = existing[0]
                new_count = record['bisect_count'] + 1
                record_id = record['id']

                update_record = {
                    "bisect_count": new_count,
                    "last_seen": current_time,
                    "related_jobs": json.dumps(record['related_jobs'] + [bad_job_id])
                }

                if not process_client.update("regression", record_id, update_record):
                    logger.error(f"更新记录失败 | ErrorID: {error_id}")

            logger.info(f"Regression updated | ErrorID: {error_id}")

        except Exception as e:
            logger.error(f"Failed to update regression: {str(e)}")
            logger.error(f"Task: {task} | Result: {result}")

    def submit_bisect_tasks(self, bisect_tasks):
        """
        Submit a list of bisect tasks to the scheduler if they are not already in the database.
        Each task is checked against the database to avoid duplicate submissions.

        :param bisect_tasks: List of bisect tasks to submit.
        """
        # Define the query to check if a bisect task already exists in the database

        # Process each bisect task
        for bisect_task in bisect_tasks:
            task_id = bisect_task["id"]
            try:
                # Check if the task already exists in the database
                result = self.submit_bisect_job(bisect_task["bad_job_id"], bisect_task["error_id"])
                if result:
                    logger.info(f"Submitted bisect task to scheduler: {bisect_task['id']}")
                else:
                    logger.error(f"Submission failed for task {task_id}")
            except KeyError as e:
                # 处理任务数据格式错误
                logger.error(f"Invalid task format {task_id}: missing {str(e)}")
            except Exception as e:
                # 添加重试机制
                retry_count = 0
                while retry_count < 3:
                    logger.error(f"Submission failed for task {task_id} {retry_count+1} times")
                    try:
                        result = self.submit_bisect_job(bisect_task["bad_job_id"], bisect_task["error_id"])
                        if result:
                           logger.info(f"Submitted bisect task to scheduler: {bisect_task['id']}")
                        break
                    except Exception:
                        retry_count += 1
                        time.sleep(2 ** retry_count)

    def get_tasks_from_bisect_task(self):
        """
        Search for bisect tasks with status 'wait' using Manticore SQL.
        Returns the list of tasks if found, otherwise returns None.

        :return: List of bisect tasks with status 'wait', or None if no tasks are found.
        """
        # Define SQL query
        sql = """
            SELECT * 
            FROM bisect
            WHERE bisect_status = 'wait'
            LIMIT 10
        """

        result = self.bisect_db.execute_query(sql)

        # Return the result if tasks are found, otherwise return None
        if result:
            return result
        else:
            return None

    def submit_bisect_job(self, bad_job_id, error_id):
        """
        Submit a bisect job to the scheduler using the provided bad_job_id and error_id.
        The job is submitted via a shell command, and the job ID is extracted from the response.

        :param bad_job_id: The ID of the bad job to be bisected.
        :param error_id: The error ID associated with the bad job.
        :return: The job ID if submission is successful, otherwise None.
        """

        try:
            submit_command = f"{os.environ['LKP_SRC']}/sbin/submit runtime=36000 bad_job_id={bad_job_id} error_id={error_id} bisect-py.yaml"
            result = subprocess.run(
            submit_command,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60)
            match = re.search(r'id=(\S+)', result.stdout)
            if match:
                job_id = match.group(1)
                logger.info(f"Job submitted successfully. Job ID: {job_id}")
                return job_id
            else:
                logger.error(f"Unexpected submit output: {result.stdout}")
                return None
        except subprocess.CalledProcessError as e:
            logger.error(f"Job submission failed with return code {e.returncode}.")
            return None
        except subprocess.TimeoutExpired:
            # 处理命令执行超时
            logger.error("Submit command timed out after 30 seconds")
            return None
        except KeyError:
            # 处理LKP_SRC环境变量缺失
            logger.error("LKP_SRC environment variable not configured")
            return None
        except Exception as e:
            # 兜底异常处理
            logger.error(f"Unexpected error during job submission: {str(e)}")
            return None

    def get_new_bisect_task_from_jobs(self):
        """
        Fetch new bisect tasks using Manticore SQL for both PKGBUILD and SS suites.
        Tasks are filtered based on a white list of error IDs and processed into a standardized format.

        :return: A list of processed tasks that match the white list criteria.
        """
        # Define SQL for PKGBUILD tasks
        # TODO: 不应该添加重复的 bad_job_id, 避免找不到 _url 的内容被查找
        # 增加判断 AND submit_time > NOW() - INTERVAL 7 DAY
        # Perf monitor
        sql_failure = """
            SELECT id, errid as errid, j.suite as suite, full_text_kv as text
            FROM jobs
            WHERE j.errid IS NOT NULL
            AND (j.program.makepkg._url IS NOT NULL OR j.ss IS NOT NULL)
            AND MATCH('job_health=abort job_stage=finish')
            ORDER BY id DESC
            LIMIT 1000
        """
        # select id, errid, full_text_kv from jobs where match('job_health=abort job_stage=finish') and j.errid is not null and j.program is not null order by id desc limit 1000
        # Define the white list of error IDs
        sql_error_id = """
            SELECT errid
            FROM regression
            WHERE record_type = 'errid'
            AND valid = 'true'
            ORDER BY id DESC
        """
        # TODO: 一个 bad_job_id 应该和白名单判断一次
        errid_white_list_raw = self.regression_db.execute_query(sql_error_id)
        errid_white_list = {item['errid'] for item in errid_white_list_raw} if errid_white_list_raw else set()

        # Execute Manticore SQL queries
        result = self.jobs_db.execute_query(sql_failure)
        # Convert the list of tasks into a dictionary with task IDs as keys
        # 添加详细日志记录原始数据格式 
        # Process the tasks to filter and transform them based on the white list
        errid_tasks = self.process_data(result, errid_white_list)
        # TODO: PERF_TASKS = self.
        # Return the processed tasks
        return errid_tasks

    def process_data(self, input_data, white_list):
        result = []
        for item in input_data:
            try:
                bad_job_id = str(item["id"])
                # 修改点：直接分割字符串代替JSON解析
                errids = item["errid"].split()  # 按空格分割字符串
                
                # 核心逻辑：优先白名单，无匹配则全处理
                if white_list:  # 模式一：存在白名单时
                    candidates = set(errids) & set(white_list)
                    if not candidates:  # 白名单存在但无匹配时回退
                        candidates = errids
                else:  # 模式二：无白名单时
                    candidates = errids

                # 生成任务文档
                for errid in candidates:
                    result.append({
                        "bad_job_id": bad_job_id,
                        "error_id": errid,
                        "bisect_status": "wait"
                    })

            except (KeyError, AttributeError) as e:  # 修改异常类型
                logger.warning(f"处理异常条目 {item.get('id')}：{str(e)}")
                continue
        
        logger.info(f"生成任务数：{len(result)} | 白名单模式：{bool(white_list)}")
        return result

    def _start_monitor(self):
        def monitor():
            while True:
                try:
                    logger.info("🔍 连接池简略状态:")
                    try:
                        jobs_active = self.jobs_db.pool._cnx_queue.qsize()
                        bisect_active = self.bisect_db.pool._cnx_queue.qsize()
                        bisect_active = self.regression_db.pool._cnx_queue.qsize()
                        logger.info(f"Jobs DB 活跃连接: {jobs_active}")
                        logger.info(f"Bisect DB 活跃连接: {bisect_active}")
                        logger.info(f"Regression DB 活跃连接: {bisect_active}")
                    except AttributeError as e:
                        logger.warning(f"连接池状态获取失败: {str(e)}")
                    
                    self.jobs_db.check_connection_leaks()
                    self.bisect_db.check_connection_leaks()
                    
                except Exception as e:
                    logger.error(f"监控异常: {str(e)}")
                finally:
                    time.sleep(300)
                
        threading.Thread(target=monitor, daemon=True).start()

class BisectAPI(MethodView):
    def __init__(self):
        self.bisect_api = BisectTask()

    def post(self):
        task = request.json
        if not task:
            return jsonify({"error": "No data provided"}), 400
        self.bisect_api.add_bisect_task(task)
        return jsonify({"message": "Task added successfully"}), 200


class ListBisectTasksAPI(MethodView):
    def __init__(self):
        self.bisect_db = BisectDB(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=os.environ.get('MANTICORE_PORT', '9306'),
            database="bisect",
            pool_size=15
        )

    def get(self):
        try:
            # 查询所有bisect任务
            tasks = self.bisect_db.execute_query("""
                SELECT id, bad_job_id, error_id, bisect_status 
                FROM bisect 
                ORDER BY id DESC
            """)

            # 格式化输出
            formatted_tasks = []
            for task in tasks:
                formatted_tasks.append({
                    "TASk ID": task['id'],
                    "BAD JOB ID": task['bad_job_id'],
                    "ERROR ID": task['error_id'],
                    "STATUS": {'wait': 'wait', 'processing': 'processing', 'completed': 'finish', 'failed': 'failed'}.get(task['bisect_status'], 'unknown'),
                })

            response_data = {
                "total": len(formatted_tasks),
                "tasks": formatted_tasks
            }
            return json.dumps(response_data, indent=2, ensure_ascii=False), 200, {'Content-Type': 'application/json; charset=utf-8'}

        except Exception as e:
            logger.error(f"获取任务列表失败: {str(e)}")
            return jsonify({"error": "内部服务器错误"}), 500


class ListTasksByStatusAPI(MethodView):
    def __init__(self):
        self.bisect_db = BisectDB(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=os.environ.get('MANTICORE_PORT', '9306'),
            database="bisect",
            pool_size=15
        )

    def get(self):
        try:
            # 获取查询参数，默认为 'completed'
            status = request.args.get('status', 'completed')

            # 查询指定状态的任务
            sql = f"""
                SELECT id, bad_job_id, error_id, bisect_status 
                FROM bisect 
                WHERE bisect_status = '{status}'
                ORDER BY id DESC
            """
            tasks = self.bisect_db.execute_query(sql)

            # 格式化输出
            formatted_tasks = []
            for task in tasks:
                formatted_tasks.append({
                    "TASK ID": task['id'],
                    "BAD JOB ID": task['bad_job_id'],
                    "ERROR ID": task['error_id'],
                    "STATUS": {'wait': 'wait', 'processing': 'processing', 'completed': 'finish', 'failed': 'failed'}.get(task['bisect_status'], 'unknown'),
                })

            response_data = {
                "total": len(formatted_tasks),
                "tasks": formatted_tasks
            }
            return json.dumps(response_data, indent=2, ensure_ascii=False), 200, {'Content-Type': 'application/json; charset=utf-8'}

        except Exception as e:
            logger.error(f"获取任务列表失败: {str(e)}")
            return jsonify({"error": "内部服务器错误"}), 500


class DeleteFailedTasksAPI(MethodView):
    def __init__(self):
        self.bisect_db = BisectDB(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=os.environ.get('MANTICORE_PORT', '9306'),
            database="bisect",
            pool_size=15
        )

    def delete(self):
        try:
            # 执行删除操作
            result = self.bisect_db.execute_delete("""
                DELETE FROM bisect 
                WHERE bisect_status = 'failed'
            """)
            
            logger.info(f"成功删除{result}条失败任务")
            return jsonify({
                "status": "success",
                "deleted_count": result
            }), 200

        except Exception as e:
            logger.error(f"删除失败任务时出错: {str(e)}")
            return jsonify({
                "error": "服务器内部错误",
                "details": str(e)
            }), 500

def run_flask():
    """使用生产级 WSGI 服务器，带开发服务器回退"""
    app.add_url_rule('/new_bisect_task', view_func=BisectAPI.as_view('bisect_api'))
    app.add_url_rule('/list_bisect_tasks', view_func=ListBisectTasksAPI.as_view('list_bisect_tasks'))
    app.add_url_rule('/list_tasks_by_status', view_func=ListTasksByStatusAPI.as_view('list_tasks_by_status'))
    app.add_url_rule('/delete_failed_tasks', view_func=DeleteFailedTasksAPI.as_view('delete_failed_tasks'))
    port = int(os.environ.get('BISECT_API_PORT', 9999))
    
    try:
        from waitress import serve
        serve(app, host='0.0.0.0', port=port, threads=8)
    except ImportError:
        logger.warning("Waitress 未安装，使用开发服务器")
        app.run(host='0.0.0.0', port=port)

def main():
    try:
        executor = ThreadPoolExecutor(max_workers=3)
        run = BisectTask()
        executor.submit(run.bisect_producer)
        executor.submit(run_flask)
        executor.submit(run.bisect_consumer)

        # 主线程保持活跃
        while True:
            time.sleep(3600)  # 防止主线程退出
    except Exception as e:
        logger.error(f"Error when init_bisect_commit: {str(e)}")
        logger.error(traceback.format_exc())  # Add stack trace
        sys.exit(1)


if __name__ == "__main__":
    main()

