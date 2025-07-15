import sys
import os
import traceback
from flask import jsonify, request

sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from py_bisect import GitBisect

sys.path.append((os.environ['CCI_SRC']) + '/src/bisect/lib')
from bisect_database import BisectDB
from log_config import logger

sys.path.append((os.environ['CCI_SRC']) + '/src/bisect/app')
from task_processor import bisect_task_instance

def new_bisect_task():
    try:
        task_data = request.json
        if not task_data:
            raise ValueError("No task data provided")
            
        logger.debug(f"DEBUG - Controller received request | Data: {task_data}")
            
        result = bisect_task_instance.add_bisect_task(task_data)
            
        logger.debug(f"DEBUG - Controller operation result: {result}")
        
        if result:
            return jsonify({
                "code": 200,
                "data": None,
                "message": "Task added successfully"
            }), 200
        return jsonify({
            "code": 500,
            "data": None,
            "message": "Failed to add task"
        }), 500
    except ValueError as e:
        logger.error(f"参数错误: {str(e)}")
        return jsonify({
            "code": 400,
            "data": None,
            "message": str(e)
        }), 400
    except Exception as e:
        logger.error(f"控制器异常: {str(e)}")
        logger.error(f"异常堆栈:\n{traceback.format_exc()}")
        return jsonify({
            "code": 500,
            "data": None,
            "message": "Internal server error"
        }), 500

def list_bisect_tasks():
    try:
        db = BisectDB(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=os.environ.get('MANTICORE_PORT', '9306'),
            database="bisect",
            pool_size=15
        )
        tasks = db.execute_query("""
            SELECT id, bad_job_id, error_id, bisect_status 
            FROM bisect 
            ORDER BY id DESC
        """)
        return jsonify({"tasks": tasks}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def list_tasks_by_status(status):
    try:
        db = BisectDB(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=os.environ.get('MANTICORE_PORT', '9306'),
            database="bisect",
            pool_size=15
        )
        tasks = db.execute_query(f"""
            SELECT id, bad_job_id, error_id, bisect_status 
            FROM bisect 
            WHERE bisect_status = '{status}'
            ORDER BY id DESC
        """)
        return jsonify({"tasks": tasks}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def delete_failed_tasks():
    try:
        db = BisectDB(
            host=os.environ.get('MANTICORE_HOST', 'localhost'),
            port=os.environ.get('MANTICORE_PORT', '9306'),
            database="bisect",
            pool_size=15
        )
        deleted_count = db.execute_delete("""
            DELETE FROM bisect 
            WHERE bisect_status = 'failed'
        """)
        return jsonify({
            "status": "success",
            "deleted_count": deleted_count
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
