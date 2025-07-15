from flask import jsonify, request
from app.task_processor import bisect_task_instance
from lib.bisect_database import BisectDB
import os

def new_bisect_task():
    task_data = request.json
    if not task_data:
        return jsonify({"error": "No data provided"}), 400
    if bisect_task_instance.add_bisect_task(task_data):
        return jsonify({"message": "Task added successfully"}), 200
    return jsonify({"error": "Failed to add task"}), 500

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
