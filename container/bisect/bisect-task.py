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
import yaml
import hashlib
import os
import sys
import uuid
import shutil
import time
import threading
import logging
import traceback
from flask import Flask, jsonify, request
from flask.views import MethodView
from httpx import RequestError

sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from py_bisect import GitBisect
import mysql.connector
from mysql.connector import Error


app = Flask(__name__)



class BisectTask:
    def __init__(self):
        self.bisect_task = None

    def add_bisect_task(self, task):
        """
        Add a new bisect task to the Elasticsearch 'bisect_task' index.

        Args:
          task (dict): A dictionary containing task information. It must include the following fields:
            - bad_job_id: The associated bad job ID.
            - error_id: The associated error ID.

        Returns:
          bool: Whether the task was successfully added.
        """
        # Parameter validation
        required_fields = ["bad_job_id", "error_id"]
        for field in required_fields:
            if field not in task:
                raise ValueError(f"Missing required field: {field}")

        job_info = self.get_job_info_from_manticore(task["bad_job_id"]) 
        print(job_info)
        error_id = job_info.get('error_id') or "none"
        suite = job_info.get('suite') or "none"
        repo = job_info.get('upstream_repo') or "none"
        task_fingerprint = hashlib.sha256((error_id+suite+repo).encode()).hexdigest()

        if self.manticore_query(f'SELECT * FROM bisect_task WHERE id={task_fingerprint}'):
            logging.info(f"Task already exists: bad_job_id={task['bad_job_id']}, error_id={task['error_id']}, id={task_fingerprint}")
            return False
        try:
            # Set priority_level
            task["priority_level"] = self.set_priority_level(job_info) 
            task["bisect_status"] = "wait"
            task["id"] = task_fingerprint
            # If the task does not exist, add it to the 'bisect_task' index
            self.manticore_insert("")
            logging.info(f"Added new task to bisect_index: {task} with {task_fingerprint}")
            return True
        except Exception as e:
            logging.error(f"Failed to add task: {e}")
            return False

    def get_job_info_from_manticore(self, job_id):
        job_json = self.manticore_query(f'SELECT j FROM jobs WHERE id={job_id}')
        if not job_json:
            return {}
        first_row = job_json[0]
        return  json.loads(first_row.get('j', {}))

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
        """
        Producer function to fetch new bisect tasks from Elasticsearch and add them to the bisect index if they don't already exist.
        This function runs in an infinite loop, checking for new tasks every 5 minutes.
        """
        error_count = 0
        while True:
            cycle_start = time.time()
            try:
                logging.info("Starting producer cycle...")
                # Fetch new bisect tasks from Elasticsearch
                new_bisect_tasks = self.get_new_bisect_task_from_manticore()
                logging.info(f"Found {len(new_bisect_tasks)} new bisect tasks")
                logging.debug(f"Raw tasks data: {new_bisect_tasks}")

                # Process each task
                processed_count = 0
                for task in new_bisect_tasks:
                    try:
                        self.add_bisect_task(task)
                    except Exception as e:
                        logging.error(f"Error processing task {task.get('id', 'unknown')}: {str(e)}")
                        continue

            except Exception as e:
                # 添加详细错误日志
                logging.error(f"Error in bisect_producer: {str(e)}")
                logging.error(f"Failed task data: {task if 'task' in locals() else 'No task data'}")
                logging.error(traceback.format_exc())  # 打印完整堆栈跟踪
                # 指数退避重试机制
                sleep_time = min(300, 2 ** error_count)
                time.sleep(sleep_time)
                error_count += 1
            else:
                # 正常执行后重置错误计数器
                error_count = 0
                cycle_time = time.time() - cycle_start
                logging.info(f"Producer cycle completed. Processed {processed_count} tasks in {cycle_time:.2f} seconds")
                # 固定间隔休眠，两个循环之间的间隔永远为300秒，无论每次循环的执行时间为多少
                sleep_time = 300 - cycle_time
                logging.info(f"Sleeping for {sleep_time:.2f} seconds until next cycle")
                time.sleep(sleep_time)

    def bisect_consumer(self):
        """
        Consumer function to fetch bisect tasks from Elasticsearch and process them.
        This function runs in an infinite loop, checking for tasks every 30 seconds.
        Tasks are either submitted to a scheduler or run locally, depending on the environment variable 'bisect_mode'.
        """
        while True:
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
                        logging.debug("Submitting bisect tasks to scheduler")
                        self.submit_bisect_tasks(bisect_tasks)
                    else:
                        # If mode is not 'submit', run tasks locally
                        logging.debug("Running bisect tasks locally")
                        self.run_bisect_tasks(bisect_tasks)
                processed = len(bisect_tasks)

            except Exception as e:
                # Log any errors that occur during task processing
                logging.error(f"Error in bisect_consumer: {e}")
                # 异常后休眠时间加倍（简易熔断机制）
                time.sleep(60)
            finally:
                # 记录处理指标
                cycle_time = time.time() - cycle_start
                logging.info(f"Consumer cycle processed {processed} tasks in {cycle_time:.2f}s")

                # 动态休眠控制（无任务时延长休眠）
                sleep_time = 30 if processed > 0 else 60
                time.sleep(max(10, sleep_time - cycle_time))  # 保证最小间隔

    def run_bisect_tasks(self, bisect_tasks):
        """
        Process a list of bisect tasks locally by running Git bisect to find the first bad commit.
        Updates the task status in Elasticsearch to 'processing' before starting the bisect process,
        and updates the result after the bisect process completes.

        :param bisect_tasks: List of bisect tasks to process.
        """
        for bisect_task in bisect_tasks:
            task_id = bisect_task.get('id', 'unknown')
            print(bisect_task)
            try:
                #检查bisect_task的状态，乐观锁
                if bisect_task.get('bisect_status') != 'wait':
                    logging.warning(f"Skipping task {task_id} with invalid status: {bisect_task['bisect_status']}")
                    continue
                # Update task status to 'processing' in Elasticsearch
                bisect_task["bisect_status"] = "processing"
                # Convert to Manticore SQL update
                update_sql = f"""
                    UPDATE bisect_task 
                    SET bisect_status = 'processing' 
                    WHERE id = '{bisect_task["id"]}'
                """
                #TODO UPDATE
                self.manticore_update(update_sql)
                logging.debug(f"Started processing task: {bisect_task['id']}")

                # Prepare task data for Git bisect with result root
                # Create unique temporary directory with cleanup
                task_id = str(bisect_task['id'])
                # Create unique clone path using task ID
                clone_path = os.path.join(
                )
                task = {
                    'bad_job_id': bisect_task['bad_job_id'],
                    'error_id': bisect_task['error_id'],
                    'bisect_result_root': f"/tmp/bisect/{bisect_task['bad_job_id']}",
                    'clone_path': clone_path
                }
                if os.path.exists(task['bisect_result_root']):
                    shutil.rmtree(task['bisect_result_root'])
                os.makedirs(task['bisect_result_root'], exist_ok=True)

                # Handle bad_job_id conversion with validation
                try:
                    gb = GitBisect()
                    result = gb.find_first_bad_commit(task)
                except (ValueError, KeyError) as e:
                    raise ValueError(f"Invalid bad_job_id: {task.get('bad_job_id')}") from e

                # Update task status and result in Elasticsearch
                bisect_task["bisect_status"] = "completed"
                bisect_task["bisect_result"] = result
                # Convert to Manticore SQL update
                update_sql = f"""
                    UPDATE bisect_task 
                    SET bisect_status = 'completed',
                        bisect_result = '{json.dumps(bisect_task["bisect_result"])}' 
                    WHERE id = {bisect_task["id"]}
                """
                # TODO update
                self.manticore_update(update_sql)
                logging.debug(f"Completed processing task: {bisect_task['id']}")

            except Exception as e:
                # Update task status to 'failed' in case of an error
                bisect_task["bisect_status"] = "failed"
                bisect_task["bisect_result"] = str(e)
                # Convert to Manticore SQL update
                # Remove bisect_result column from update
                update_sql = f"""
                    UPDATE bisect_task 
                    SET bisect_status = 'failed' 
                    WHERE id = '{bisect_task["id"]}'
                """
                self.manticore_query(update_sql)
                logging.error(f"Marked task {bisect_task['id']} as failed due to error: {e}")

    def submit_bisect_tasks(self, bisect_tasks):
        """
        Submit a list of bisect tasks to the scheduler if they are not already in the database.
        Each task is checked against the database to avoid duplicate submissions.

        :param bisect_tasks: List of bisect tasks to submit.
        """
        # Define the query to check if a bisect task already exists in the database
        query_if_bisect_already_in_db = {
            "_source": ["id"],  # 只需返回ID字段验证存在性
            "query": {
                "bool": {
                    "must": [
                        {"term": {"error_id": None}},  # 占位符，实际替换具体值
                        {"term": {"bad_job_id": None}},
                        {"exists": {"field": "id"}},
                        {"term": {"suite": "bisect-py"}}
                    ]
                }
            }
        }

        # Process each bisect task
        for bisect_task in bisect_tasks:
            task_id = bisect_task["id"]
            try:
                # Check if the task already exists in the database
                current_query = query_if_bisect_already_in_db.copy()
                current_query["query"]["bool"]["must"][0]["term"]["error_id"] = bisect_task["error_id"]
                current_query["query"]["bool"]["must"][1]["term"]["bad_job_id"] = bisect_task["bad_job_id"]
                if not self.es_query("jobs8", current_query):
                    # If the task does not exist, submit it to the scheduler
                    result = self.submit_bisect_job(bisect_task["bad_job_id"], bisect_task["error_id"])
                    if result:
                        logging.info(f"Submitted bisect task to scheduler: {bisect_task['id']}")
                    else:
                        logging.error(f"Submission failed for task {task_id}")
                else:
                    # If the task already exists, log a message
                    logging.debug(f"Job already in db: {bisect_task['id']}")
            except KeyError as e:
                # 处理任务数据格式错误
                logging.error(f"Invalid task format {task_id}: missing {str(e)}")
            except Exception as e:
                # 添加重试机制
                retry_count = 0
                while retry_count < 3:
                    logging.error(f"Submission failed for task {task_id} {retry_count+1} times")
                    try:
                        current_query = query_if_bisect_already_in_db.copy()
                        current_query["query"]["bool"]["must"][0]["term"]["error_id"] = bisect_task["error_id"]
                        current_query["query"]["bool"]["must"][1]["term"]["bad_job_id"] = bisect_task["bad_job_id"]
                        if not self.es_query("jobs8", current_query):
                            result = self.submit_bisect_job(bisect_task["bad_job_id"], bisect_task["error_id"])
                            if result:
                                logging.info(f"Submitted bisect task to scheduler: {bisect_task['id']}")
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
            FROM bisect_task 
            WHERE bisect_status = 'wait'
            LIMIT 100
        """

        result = self.manticore_query(sql)

        # Return the result if tasks are found, otherwise return None
        if result:
            return result
        else:
            return None

        
    def execute_sql(self, sql, db=None, write_operation=False):
        """Base method for executing SQL statements"""
        try:
            host = os.environ.get('MANTICORE_HOST', 'localhost')
            port = os.environ.get('MANTICORE_PORT', '9306') 
            database = db or os.environ.get('MANTICORE_DB', 'jobs')

            connection = mysql.connector.connect(
                host=host,
                port=port,
                database=database,
                connect_timeout=5
            )

            cursor = connection.cursor(dictionary=True)
            
            if write_operation:
                cursor.execute(sql)
                connection.commit()
                return cursor.rowcount
            else:
                cursor.execute(sql)
                result = cursor.fetchall()
                if cursor.with_rows:
                    cursor.fetchall()  # Consume unread results
                return result if result else None

        except mysql.connector.Error as e:
            logging.error(f"Manticore operation failed: {e}\nSQL: {sql}")
            return None
        except Exception as e:
            logging.error(f"Unexpected error: {str(e)}\nSQL: {sql}")
            return None
        finally:
            if 'cursor' in locals():
                cursor.close()
            if 'connection' in locals() and connection.is_connected():
                connection.close()

    def manticore_query(self, sql, db=None):
        """Execute read query and return results"""
        return self.execute_sql(sql, db, write_operation=False)

    def manticore_insert(self, table, data, db=None):
        """Safe INSERT operation with parameterized query"""
        if not data:
            return None
            
        columns = ', '.join(data.keys())
        values = ', '.join([f"'{v}'" if isinstance(v, str) else str(v) for v in data.values()])
        sql = f"INSERT INTO {table} ({columns}) VALUES ({values})"
        
        return self.execute_sql(sql, db, write_operation=True)

    def manticore_update(self, table, updates, condition, db=None):
        """Safe UPDATE operation with parameterized query"""
        if not updates or not condition:
            return None

        set_clause = ', '.join([
            f"{k} = '{v}'" if isinstance(v, str) else f"{k} = {v}" 
            for k, v in updates.items()
        ])
        where_clause = ' AND '.join([
            f"{k} = '{v}'" if isinstance(v, str) else f"{k} = {v}"
            for k, v in condition.items() 
        ])
        sql = f"UPDATE {table} SET {set_clause} WHERE {where_clause}"
        
        return self.execute_sql(sql, db, write_operation=True)

    def manticore_delete(self, table, condition, db=None):
        """Safe DELETE operation with parameterized query"""
        if not condition:
            return None

        where_clause = ' AND '.join([
            f"{k} = '{v}'" if isinstance(v, str) else f"{k} = {v}"
            for k, v in condition.items()
        ])
        sql = f"DELETE FROM {table} WHERE {where_clause}"
        
        return self.execute_sql(sql, db, write_operation=True)

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
                logging.info(f"Job submitted successfully. Job ID: {job_id}")
                return job_id
            else:
                logging.error(f"Unexpected submit output: {result.stdout}")
                return None
        except subprocess.CalledProcessError as e:
            logging.error(f"Job submission failed with return code {e.returncode}.")
            return None
        except subprocess.TimeoutExpired:
            # 处理命令执行超时
            logging.error("Submit command timed out after 30 seconds")
            return None
        except KeyError:
            # 处理LKP_SRC环境变量缺失
            logging.error("LKP_SRC environment variable not configured")
            return None
        except Exception as e:
            # 兜底异常处理
            logging.error(f"Unexpected error during job submission: {str(e)}")
            return None

    def get_new_bisect_task_from_manticore(self):
        """
        Fetch new bisect tasks using Manticore SQL for both PKGBUILD and SS suites.
        Tasks are filtered based on a white list of error IDs and processed into a standardized format.

        :return: A list of processed tasks that match the white list criteria.
        """
        # Define SQL for PKGBUILD tasks
        # TODO: AND submit_time > NOW() - INTERVAL 7 DAY
        sql_failure = """
            SELECT id, j.stats as errid
            FROM jobs 
            WHERE j.job_health = 'abort' 
              AND j.stats IS NOT NULL
            ORDER BY id DESC
        """

        # Define SQL for SS tasks
        sql_ss = """
            SELECT id, stats, ss
            FROM jobs
            WHERE job_health = 'failed'
              AND ss IS NOT NULL
              AND stats IS NOT NULL
        """

        # Define the white list of error IDs
        errid_white_list = ["last_state.eid.test..exit_code.99"]

        # Execute Manticore SQL queries
        result = self.manticore_query(sql_failure)

        # Convert the list of tasks into a dictionary with task IDs as keys
        # 添加详细日志记录原始数据格式
        logging.debug(f"Raw query result sample: {result[:1] if result else 'Empty result'}")
        
        result_dict = {}
        for item in result:
            try:
                item_id = item['id']
                result_dict[item_id] = item
            except KeyError:
                logging.warning(f"Skipping invalid item missing 'id' field: {item}")
        # Process the tasks to filter and transform them based on the white list
        tasks = self.process_data(result, errid_white_list)

        # Return the processed tasks
        return tasks

    def process_data(self, input_data, white_list):
        """
        Process input data to filter and transform it based on a white list of error IDs.
        Each valid entry is assigned a new UUID and added to the result list.

        :param input_data: A list of dictionaries containing the input data to process
        :param white_list: A list of error IDs to filter by.
        :return: A list of processed documents, each containing a new UUID and filtered error ID.
        """
        result = []

        # Iterate over each item in the input list
        for item in input_data:
            try:
                # Parse the JSON string in errid field
                error_ids = json.loads(item["errid"]).keys()
                
                # Find matching error IDs from white list
                matches = [errid for errid in error_ids if errid in white_list]
                if not matches:
                    continue
                
                # Create new document with generated UUID and original bad_job_id
                document = {
                    "id": str(uuid.uuid4()),  # Generate UUID for task ID
                    "bad_job_id": str(item["id"]),  # Keep original as string
                    "error_id": matches[0],
                    "bisect_status": "wait"
                }
                result.append(document)
                
            except (KeyError, json.JSONDecodeError) as e:
                logging.warning(f"Skipping invalid item {item.get('id')}: {str(e)}")

        return result

    def check_existing_bisect_task(self, bad_job_id, error_id):
        """
        Check if a bisect task with the given bad_job_id and error_id already exists using Manticore SQL.

        :param bad_job_id: The ID of the bad job to check.
        :param error_id: The error ID associated with the bad job.
        :return: Boolean indicating if task exists.
        """
        sql = f"""
            SELECT 1 AS exist 
            FROM bisect_task 
            WHERE bad_job_id = '{bad_job_id}' 
              AND error_id = '{error_id}' 
            LIMIT 1
        """

        try:
            result = self.manticore_query(sql, db="bisect_task")
            if not result:  # Handle None result
                logging.warning(f"No results from existence check query for {bad_job_id}/{error_id}")
                return False
                
            return result

        except KeyError as e:
            logging.error(f"manticore response structure: {str(e)}")
            return True
        except Exception as e:
            logging.error(f"Unexpected error during existence check: {str(e)}")
            return True


class BisectAPI(MethodView):
    def __init__(self):
        self.bisect_api = BisectTask()

    def post(self):
        task = request.json
        print(task)
        if not task:
            return jsonify({"error": "No data provided"}), 400
        self.bisect_api.add_bisect_task(task)
        return jsonify({"message": "Task added successfully"}), 200

def set_log():
    stream_handler = logging.StreamHandler()
    console_formatter = logging.Formatter(
    '%(asctime)s - %(name)s - %(levelname)s - %(module)s:%(lineno)d - %(message)s'
    )

    stream_handler.setFormatter(console_formatter)
    stream_handler.setLevel(logging.DEBUG if os.getenv('LOG_LEVEL') == 'DEBUG' else logging.INFO)

    logging.basicConfig(
        level=logging.DEBUG,
        handlers=[stream_handler],
        format='%(asctime)s.%(msecs)03d %(levelname)s %(name)s:%(lineno)d - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    logger = logging.getLogger('bisect-task')
    logger.setLevel(logging.DEBUG)
    logger.addHandler(stream_handler)
    logger.propagate = False



def run_flask():
    app.add_url_rule('/new_bisect_task', view_func=BisectAPI.as_view('bisect_api'))
    app.run(host='0.0.0.0', port=9999)

def main():
    try:
        # 先启动后台任务
        set_log()
        run = BisectTask()
        bisect_producer_thread = threading.Thread(target=run.bisect_producer, daemon=True)
        bisect_producer_thread.start()
        # 在独立线程运行Flask
        flask_thread = threading.Thread(target=run_flask, daemon=True)
        flask_thread.start()

        num_consumer_threads = 2
        for i in range(num_consumer_threads):
            bisect_consumer_thread = threading.Thread(target=run.bisect_consumer, daemon=True)
            bisect_consumer_thread.start()

        # 主线程保持活跃
        while True:
            time.sleep(3600)  # 防止主线程退出
    except Exception as e:
        print("Error when init_bisect_commit:" + e)
        sys.exit(-1)


if __name__ == "__main__":
    main()
