#!/usr/bin/env python3
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2025 Huawei Technologies Co., Ltd. All rights reserved.
#   Input: ES JSON
# 
#   functions: 
#       provide API/new-bisect-task 
#           add to ES
#       loop:
#           consume one task from ES
#           fork process, start bisect


import json
import subprocess
import yaml
import os
import sys
import uuid
import time
import threading
import logging
from flask import Flask, jsonify, request
from flask.views import MethodView

sys.path.append((os.environ['CCI_SRC'])+'/src/libpy/')
from es_client import EsClient  

sys.path.append((os.environ['LKP_SRC'])+'/programs/bisect-py/')
from py_bisect import GitBisect

# Initialize client
es_client = EsClient()

app = Flask(__name__)

logging.basicConfig(level=logging.INFO)


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

        # Check if the task already exists
        if not self.check_existing_bisect_task(task["bad_job_id"], task["error_id"]):
            try:
                # If the task does not exist, add it to the 'bisect_task' index
                es_client.update_by_id("bisect_task", task["id"], task)
                logging.info(f"Added new task to bisect_index: {task}")
                return True
            except Exception as e:
                logging.error(f"Failed to add task: {e}")
                return False
        else:
            logging.info(f"Task already exists: bad_job_id={task['bad_job_id']}, error_id={task['error_id']}")
            return False

    def bisect_producer(self):
        """
        Producer function to fetch new bisect tasks from Elasticsearch and add them to the bisect index if they don't already exist.
        This function runs in an infinite loop, checking for new tasks every 5 minutes.
        """
        while True:
            try:
                # Fetch new bisect tasks from Elasticsearch
                new_bisect_tasks = self.get_new_bisect_task_from_ES()

                # Process each task
                for task in new_bisect_tasks:
                    # Check if the task already exists in the bisect index
                    if not self.check_existing_bisect_task(task["bad_job_id"], task["error_id"]):
                        # If the task does not exist, add it to the bisect index
                        es_client.update_by_id("bisect_task", task["id"], task)
                        print(f"Added new task to bisect_index: {task}")

            except Exception as e:
                # Log any errors that occur during task processing
                print(f"Error in bisect_producer: {e}")

            # Wait for 5 minutes before checking for new tasks again
            time.sleep(300)

    def bisect_consumer(self):
        """
        Consumer function to fetch bisect tasks from Elasticsearch and process them.
        This function runs in an infinite loop, checking for tasks every 30 seconds.
        Tasks are either submitted to a scheduler or run locally, depending on the environment variable 'bisect_mode'.
        """
        while True:
            try:
                # Fetch bisect tasks from Elasticsearch
                bisect_tasks = self.get_tasks_from_bisect_task()

                if bisect_tasks:  # If tasks are found
                    # Check the mode of operation from environment variable
                    if os.getenv('bisect_mode') == "submit":
                        # If mode is 'submit', send tasks to the scheduler
                        print("Submitting bisect tasks to scheduler")
                        self.submit_bisect_tasks(bisect_tasks)
                    else:
                        # If mode is not 'submit', run tasks locally
                        print("Running bisect tasks locally")
                        self.run_bisect_tasks(bisect_tasks)

            except Exception as e:
                # Log any errors that occur during task processing
                print(f"Error in bisect_consumer: {e}")

            # Wait for 30 seconds before checking for new tasks again
            time.sleep(30) 

    def run_bisect_tasks(self, bisect_tasks):
        """
        Process a list of bisect tasks locally by running Git bisect to find the first bad commit.
        Updates the task status in Elasticsearch to 'processing' before starting the bisect process,
        and updates the result after the bisect process completes.

        :param bisect_tasks: List of bisect tasks to process.
        """
        for bisect_task in bisect_tasks:
            try:
                # Update task status to 'processing' in Elasticsearch
                bisect_task["bisect_status"] = "processing"
                es_client.update_by_id("bisect_index", bisect_task["id"], bisect_task)
                print(f"Started processing task: {bisect_task['id']}")

                # Prepare task data for Git bisect
                task = {
                    'bad_job_id': bisect_task['bad_job_id'],
                    'error_id': bisect_task['error_id']
                }

                # Run Git bisect to find the first bad commit
                gb = GitBisect()
                result = gb.find_first_bad_commit(task)

                # Update task status and result in Elasticsearch
                bisect_task["bisect_status"] = "completed"
                bisect_task["bisect_result"] = result
                es_client.update_by_id("bisect_index", bisect_task["id"], bisect_task)
                print(f"Completed processing task: {bisect_task['id']}")

            except Exception as e:
                # Log any errors that occur during task processing
                print(f"Error processing task {bisect_task['id']}: {e}")

                # Update task status to 'failed' in case of an error
                bisect_task["bisect_status"] = "failed"
                bisect_task["bisect_result"] = str(e)
                es_client.update_by_id("bisect_index", bisect_task["id"], bisect_task)
                print(f"Marked task {bisect_task['id']} as failed due to error: {e}")

    def submit_bisect_tasks(self, bisect_tasks):
        """
        Submit a list of bisect tasks to the scheduler if they are not already in the database.
        Each task is checked against the database to avoid duplicate submissions.

        :param bisect_tasks: List of bisect tasks to submit.
        """
        # Define the query to check if a bisect task already exists in the database
        query_if_bisect_already_in_db = {
            "_source": ["id", "bad_job_id", "error_id"],  # Fields to return in the response
            "query": {
            "bool": {
                "must": [
                    {"exists": {"field": "error_id"}},  # Task must have an error_id
                    {"exists": {"field": "bad_job_id"}},  # Task must have a bad_job_id
                    {"exists": {"field": "id"}},  # Task must have an id
                    {"term": {"suite": "bisect-py"}}  # Task suite must be "bisect-py"
                    ]
                }
            }
        }

        # Process each bisect task
        for bisect_task in bisect_tasks:
            try:
                # Check if the task already exists in the database
                if not self.es_query("jobs8", query_if_bisect_already_in_db):
                    # If the task does not exist, submit it to the scheduler
                    result = self.submit_bisect_job(bisect_task["bad_job_id"], bisect_task["error_id"])
                    print(f"Submitted bisect task to scheduler: {bisect_task['id']}")
                else:
                    # If the task already exists, log a message
                    print(f"Job already in db: {bisect_task['id']}")

            except Exception as e:
                # Log any errors that occur during task submission
                print(f"Error submitting task {bisect_task['id']}: {e}")

    def get_tasks_from_bisect_task(self):
        """
        Search for bisect tasks in the 'bisect_task' index that have a status of 'wait'.
        Returns the list of tasks if found, otherwise returns None.
    
        :return: List of bisect tasks with status 'wait', or None if no tasks are found.
        """
        # Define the query to find bisect tasks with status 'wait'
        query_bisect_wait = {
            "query": {
                "bool": {
                    "must": [
                        {"exists": {"field": "id"}},  # Task must have an id
                        {"term": {"bisect-status": "wait"}}  # Task status must be 'wait'
                    ]
                }
            }
        }
    
        # Execute the query on the 'bisect_task' index
        result = self.es_query("bisect_task", query_bisect_wait)
    
        # Return the result if tasks are found, otherwise return None
        if result:
            return result
        else:
            return None
    
    def es_query(self, index, query):
        """
        Execute a search query on the specified Elasticsearch index and return the results.
    
        :param index: The name of the Elasticsearch index to query.
        :param query: The search query to execute, in Elasticsearch query DSL format.
        :return: The search results returned by Elasticsearch, or None if an error occurs.
        """
        try:
            # Execute the search query on the specified index
            result = es_client.search_by_query(index=index, query=query)
            return result
    
        except Exception as e:
            # Log any errors that occur during the query execution
            print(f"Error executing query on index '{index}': {e}")
            return None
    
    def submit_bisect_job(self, bad_job_id, error_id):
        """
        Submit a bisect job to the scheduler using the provided bad_job_id and error_id.
        The job is submitted via a shell command, and the job ID is extracted from the response.

        :param bad_job_id: The ID of the bad job to be bisected.
        :param error_id: The error ID associated with the bad job.
        :return: The job ID if submission is successful, otherwise None.
        """
        # Construct the submit command using environment variables and parameters
        submit_command = f"{os.environ['LKP_SRC']}/sbin/submit runtime=36000 bad_job_id={bad_job_id} error_id={error_id} bisect-py.yaml"
    
        # Execute the submit command and capture the return code and output
        retcode, response = subprocess.getstatusoutput(submit_command)
    
        # Check if the command executed successfully
        if retcode == 0:
            try:
                # Extract the job ID from the response
                # The response format is expected to contain "id=<job_id>"
                job_id = response.split("id=")[2].split("\n")[0]
                print(f"Job submitted successfully. Job ID: {job_id}")
                return job_id
            except IndexError:
                # Handle the case where the job ID cannot be parsed from the response
                print("Error parsing job ID from response.")
                return None
        else:
            # Handle the case where the job submission failed
            print(f"Job submission failed with return code {retcode}.")
            return None
    
    def get_new_bisect_task_from_ES(self):
        """
        Fetch new bisect tasks from Elasticsearch for both PKGBUILD and SS suites.
        Tasks are filtered based on a white list of error IDs and processed into a standardized format.

        :return: A list of processed tasks that match the white list criteria.
        """
        # Define the query for PKGBUILD tasks
        query_pkgbuild = {
            "_source": ["id", "errid"],  # Fields to return in the response
            "query": {
                "bool": {
                    "must": [
                        {"exists": {"field": "errid"}},  # Task must have an error ID
                        {"exists": {"field": "id"}},  # Task must have an ID
                        {"term": {"suite": "pkgbuild"}},  # Task suite must be "pkgbuild"
                        {"term": {"job_health": "failed"}}  # Task job health must be "failed"
                    ]
                }
            }
        }
    
        # Define the query for SS tasks
        query_ss = {
            "_source": ["id", "errid", "ss"],  # Fields to return in the response
            "query": {
                "bool": {
                    "must": [
                        {"exists": {"field": "errid"}},  # Task must have an error ID
                        {"exists": {"field": "ss"}},  # Task must have an SS field
                        {"exists": {"field": "id"}},  # Task must have an ID
                        {"term": {"suite": "pkgbuild"}},  # Task suite must be "pkgbuild"
                        {"term": {"job_health": "failed"}}  # Task job health must be "failed"
                    ]
                }
            }
        }
    
        # Define the white list of error IDs
        errid_white_list = ["last_state.test.pkgbuild.exit_code.1"]
    
        # Fetch PKGBUILD tasks from Elasticsearch
        result_pkgbuild = self.es_query(index="jobs8", query=query_pkgbuild)
        
        # Fetch SS tasks from Elasticsearch
        result_ss = self.es_query(index="jobs8", query=query_ss)
    
        # Combine the results from both queries
        result = result_pkgbuild + result_ss
    
        # Convert the list of tasks into a dictionary with task IDs as keys
        result_dict = {item['id']: item for item in result}
    
        # Process the tasks to filter and transform them based on the white list
        tasks = self.process_data(result_dict, errid_white_list)
    
        # Return the processed tasks
        return tasks 
    
    def process_data(self, input_data, white_list):
        """
        Process input data to filter and transform it based on a white list of error IDs.
        Each valid entry is assigned a new UUID and added to the result list.
    
        :param input_data: A dictionary containing the input data to process.
        :param white_list: A list of error IDs to filter by.
        :return: A list of processed documents, each containing a new UUID and filtered error ID.
        """
        result = []  # Initialize an empty list to store the processed documents
    
        # Iterate over each key-value pair in the input data
        for key, value in input_data.items():
            # Check if any error ID in the current entry is in the white list
            if any(errid in white_list for errid in value["errid"]):
                # Filter the error IDs to include only those in the white list
                filtered_errid = [errid for errid in value["errid"] if errid in white_list][0]
    
                # Generate a new UUID for the document
                new_id = str(uuid.uuid4())
    
                # Create a new document with the filtered data
                document = {
                    "id": new_id,  # Assign the new UUID as the document ID
                    "bad_job_id": value["id"],  # Copy the bad job ID from the input data
                    "error_id": filtered_errid,  # Use the filtered error ID
                    "bisect_status": "wait"  # Set the initial bisect status to "wait"
                }
    
                # Add the new document to the result list
                result.append(document)
    
        # Return the list of processed documents
        return result
    
    def check_existing_bisect_task(self, bad_job_id, error_id):
        """
        Check if a bisect task with the given bad_job_id and error_id already exists in the 'bisect_task' index.
    
        :param bad_job_id: The ID of the bad job to check.
        :param error_id: The error ID associated with the bad job.
        :return: The search results from Elasticsearch if the task exists, otherwise None.
        """
        # Define the query to check for an existing bisect task
        query = {
            "query": {
                "bool": {
                    "must": [
                        {"term": {"bad_job_id": bad_job_id}},  # Task must have the specified bad_job_id
                        {"term": {"error_id": error_id}}  # Task must have the specified error_id
                    ]
                }
            }
        }
    
        # Execute the query on the 'bisect_task' index
        response = self.es_query(index="bisect_task", query=query)
    
        # Print the response for debugging purposes
        print(f"Query response for bad_job_id={bad_job_id}, error_id={error_id}: {response}")
 
        # Return the response (search results or None)
        return response
 
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

def main():
    try:
        app.add_url_rule('/new_bisect_task', view_func=BisectAPI.as_view('bisect_api'))
        app.run(host='0.0.0.0', port=9999)
        run = BisectTask()
        bisect_producer_thread = threading.Thread(target=run.bisect_producer)
        bisect_producer_thread.start()

        num_consumer_threads = 2
        for i in range(num_consumer_threads):
            bisect_consumer_thread = threading.Thread(target=run.bisect_consumer)
            bisect_consumer_thread.start()

        bisect_producer_thread.join()
        for bisect_consumer_thread in threading.enumerate():
            if bisect_consumer_thread != threading.current_thread():
                bisect_consumer_thread.join()
    except Exception as e:
        print("Error when init_bisect_commit:"+e)
        sys.exit(-1)

if __name__ == "__main__":
    main()
