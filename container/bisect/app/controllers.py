"""Flask controller layer for bisect task APIs and admin operations."""

import sys
import os
import time
import traceback
from datetime import datetime, timezone
from flask import jsonify, request
import threading

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from config import Config
from log_config import logger
from query_builder import build_task_query_conditions, build_condition_summary, _escape_sql_string

sys.path.append((os.environ['LKP_SRC']) + '/sbin/bisect/')
from lkp_bisect.core.git_bisect import GitBisect
from lkp_bisect.db.manticore import ManticoreClient

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/core')
from task_processor import bisect_task_instance

# Import pool monitoring service
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect')
from services.pool_monitor_service import PoolMonitorService


def _get_manticore_client():
    """Get ManticoreSearch HTTP client"""
    return ManticoreClient(
        host=os.environ.get('MANTICORE_HOST', 'localhost'),
        port=int(os.environ.get('MANTICORE_WRITE_PORT', '9308'))
    )

# Timestamp fields to add human-readable versions for
_TIMESTAMP_FIELDS = ('submit_time', 'updated_at', 'created_at')

def _humanize_timestamps(task: dict) -> dict:
    """Add '_human' suffix fields for unix timestamp fields (e.g. updated_at_human).

    Original numeric fields are kept intact for backward compatibility.
    """
    for field in _TIMESTAMP_FIELDS:
        value = task.get(field)
        if isinstance(value, (int, float)) and value > 0:
            task[f'{field}_human'] = datetime.fromtimestamp(value, tz=timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
    return task

def _humanize_task_list(tasks):
    """Apply timestamp humanization to a list of tasks."""
    if not tasks:
        return tasks
    return [_humanize_timestamps(t) for t in tasks]

def new_bisect_task():
    try:
        task_data = request.json
        if not task_data:
            raise ValueError("No task data provided")
            
        # API-level validation: normalize null `j` payload.
        if 'j' in task_data and task_data['j'] is None:
            logger.warning("API request has null j field; normalizing to empty object")
            task_data['j'] = {}
            
        logger.debug(f"DEBUG - Controller received request | Data: {task_data}")
            
        result = bisect_task_instance.add_bisect_task(task_data, priority=999)
            
        logger.debug(f"DEBUG - Controller operation result: {result}")
        
        # 
        if isinstance(result, dict):
            if result['status'] == 'created':
                return jsonify({
                    "code": 200,
                    "data": {"task_id": result.get('task_id')},
                    "message": result['message']
                }), 200
            elif result['status'] == 'pending_verification':
                return jsonify({
                    "code": 200,
                    "data": {"task_id": result.get('task_id')},
                    "message": result['message']
                }), 200
            elif result['status'] == 'duplicate':
                return jsonify({
                    "code": 409,  # Conflict - 
                    "data": None,
                    "message": result['message']
                }), 409
            else:  # failed or error
                return jsonify({
                    "code": 500,
                    "data": None,
                    "message": result['message']
                }), 500
        else:
            # 
            if result:
                return jsonify({
                    "code": 200,
                    "data": None,
                    "message": "Task added successfully"
                }), 200
            else:
                return jsonify({
                    "code": 500,
                    "data": None,
                    "message": "Failed to add task"
                }), 500
    except ValueError as e:
        logger.error(f"Parameter error: {str(e)}")
        return jsonify({
            "code": 400,
            "data": None,
            "message": str(e)
        }), 400
    except Exception as e:
        logger.error(f"Controller exception: {str(e)}")
        logger.error(f"Exception traceback:\n{traceback.format_exc()}")
        return jsonify({
            "code": 500,
            "data": None,
            "message": "Internal server error"
        }), 500

def list_bisect_tasks():
    """
    bisecttask, supportconditions

    query:
    - status: taskstatus (wait/processing/success/failed/verifying/pending_verification)
    - error_id: filter by exact error ID
    - bad_job_id: bad_job_id
    - category:  (functional/performance/build)
    - hours: Ntask
    - git_url: fuzzy match by repository URL
    - task_id: taskID
    - task_ids: multiple task IDs (comma-separated)
    - first_bad_commit: filter by full or short SHA
    - limit: count (default Config.DEFAULT_QUERY_LIMIT)
    """
    try:
        client = _get_manticore_client()

        # query
        where_clause, filters = build_task_query_conditions()

        # get limit 
        limit = request.args.get('limit', str(Config.DEFAULT_QUERY_LIMIT))
        try:
            limit = int(limit)
            limit = max(1, min(limit, Config.MAX_QUERY_LIMIT))
        except ValueError:
            limit = Config.DEFAULT_QUERY_LIMIT

        #  SQL query
        sql_query = f"""
            SELECT id, * FROM bisect
            WHERE {where_clause}
            ORDER BY id DESC
            LIMIT {limit}
            OPTION max_matches={limit}
        """

        logger.debug(f"query: {sql_query}")
        tasks = client.sql_select(sql_query)

        result_count = len(tasks) if tasks else 0

        return jsonify({
            "tasks": _humanize_task_list(tasks) or [],
            "count": result_count,
            "filters": filters,
            "limit": limit
        }), 200
    except Exception as e:
        logger.error(f"Error listing bisect tasks: {str(e)}")
        return jsonify({"error": str(e)}), 500



def thread_pool_status():
    """getstatus"""
    try:
        # Python 3.11fixed: _tasks_donenot found
        completed_tasks = 0
        try:
            completed_tasks = bisect_task_instance.thread_pool._work_queue._tasks_done
        except AttributeError:
            # Python 3.11+  SimpleQueue  _tasks_done 
            completed_tasks = "Not available (Python 3.11+)"
        
        status = {
            "max_workers": bisect_task_instance.thread_pool._max_workers,
            "active_threads": threading.active_count() - 1,  # 
            "pending_tasks": bisect_task_instance.thread_pool._work_queue.qsize(),
            "completed_tasks": completed_tasks
        }
        return jsonify(status), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def toggle_producer():
    """status"""
    try:
        state = request.args.get('state')
        if state not in ['enable', 'disable']:
            return jsonify({"error": "Invalid state. Use 'enable' or 'disable'"}), 400
        
        old_state = Config.BISECT_PRODUCER_ENABLED
        Config.BISECT_PRODUCER_ENABLED = (state == 'enable')
        
        # , not found, 
        if not old_state and Config.BISECT_PRODUCER_ENABLED:
            # check
            producer_thread_exists = False
            for thread in threading.enumerate():
                if hasattr(thread, '_target') and thread._target:
                    if 'bisect_producer' in str(thread._target.__name__ if hasattr(thread._target, '__name__') else thread._target):
                        producer_thread_exists = True
                        break
                elif hasattr(thread, 'name') and 'producer' in thread.name.lower():
                    producer_thread_exists = True
                    break
                    
            if not producer_thread_exists:
                # 
                producer_thread = threading.Thread(
                    target=bisect_task_instance.bisect_producer, 
                    daemon=True,
                    name="BisectProducer"
                )
                producer_thread.start()
                logger.info("A new producer thread was started via API")
        
        logger.info(f"Producer state switched: {'enabled' if Config.BISECT_PRODUCER_ENABLED else 'disabled'}")
        return jsonify({
            "status": "success",
            "producer_enabled": Config.BISECT_PRODUCER_ENABLED,
            "old_state": old_state,
            "action": "started new thread" if (not old_state and Config.BISECT_PRODUCER_ENABLED) else "configuration updated"
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def get_producer_status():
    """getstatus"""
    try:
        # checkconfigstatus
        config_enabled = Config.BISECT_PRODUCER_ENABLED
        
        # check
        producer_threads = []
        for thread in threading.enumerate():
            is_producer = False
            
            # check
            if hasattr(thread, '_target') and thread._target:
                if 'bisect_producer' in str(thread._target.__name__ if hasattr(thread._target, '__name__') else thread._target):
                    is_producer = True
            
            # check
            if hasattr(thread, 'name') and 'producer' in thread.name.lower():
                is_producer = True
                
            if is_producer:
                producer_threads.append({
                    "name": thread.name,
                    "is_alive": thread.is_alive(),
                    "daemon": thread.daemon,
                    "target": str(thread._target.__name__ if hasattr(thread, '_target') and hasattr(thread._target, '__name__') else 'unknown')
                })
        
        return jsonify({
            "producer_enabled": config_enabled,
            "active_producer_threads": len(producer_threads),
            "producer_threads": producer_threads,
            "total_threads": threading.active_count()
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def reset_processing_tasks():
    """
    resetprocessingstatus taskswaitstatus

    supportquery conditions:
    - category: 
    - hours: N
    - git_url: repo
     ( query_builder supportconditions)
    """
    try:
        client = _get_manticore_client()

        # query
        where_clause, filters = build_task_query_conditions()

        #  status, default processing
        if 'status' not in filters:
            if where_clause == "1=1":
                where_clause = "bisect_status = 'processing'"
            else:
                where_clause = f"bisect_status = 'processing' AND {where_clause}"
            filters['status'] = 'processing'

        # statscount
        count_query = f"""
            SELECT COUNT(*) as count
            FROM bisect
            WHERE {where_clause}
        """
        count_result = client.sql_select(count_query)
        count = count_result[0]['count'] if count_result else 0

        if count == 0:
            return jsonify({
                "status": "success",
                "message": "No processing tasks to reset",
                "reset_count": 0,
                "filters": filters
            }), 200

        # reset
        current_time = int(time.time())
        update_query = f"""
            UPDATE bisect
            SET bisect_status = 'wait',
                updated_at = {current_time},
                submit_time = {current_time}
            WHERE {where_clause}
        """

        client.sql_raw(update_query)

        condition_summary = build_condition_summary(filters)
        logger.info(f"API reset | count: {count} | conditions: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} processing tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"reset processing tasks failed: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def reset_failed_tasks():
    """
    Reset failed tasks to wait status

    supportquery conditions:
    - category: 
    - hours: N
    - git_url: repo
     ( query_builder supportconditions)
    """
    try:
        client = _get_manticore_client()

        # query
        where_clause, filters = build_task_query_conditions()

        #  status, default failed
        if 'status' not in filters:
            if where_clause == "1=1":
                where_clause = "bisect_status = 'failed'"
            else:
                where_clause = f"bisect_status = 'failed' AND {where_clause}"
            filters['status'] = 'failed'

        # statscount
        count_query = f"""
            SELECT COUNT(*) as count
            FROM bisect
            WHERE {where_clause}
        """
        count_result = client.sql_select(count_query)
        count = count_result[0]['count'] if count_result else 0

        if count == 0:
            return jsonify({
                "status": "success",
                "message": "No failed tasks to reset",
                "reset_count": 0,
                "filters": filters
            }), 200

        # reset ( last_error)
        current_time = int(time.time())
        update_query = f"""
            UPDATE bisect
            SET bisect_status = 'wait',
                last_error = '',
                updated_at = {current_time},
                submit_time = {current_time}
            WHERE {where_clause}
        """

        client.sql_raw(update_query)

        condition_summary = build_condition_summary(filters)
        logger.info(f"API reset | count: {count} | conditions: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} failed tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"reset failed tasks failed: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def reset_verifying_tasks():
    """
    Reset verifying tasks to wait status

    supportquery conditions:
    - category: 
    - hours: N
    - git_url: repo
     ( query_builder supportconditions)
    """
    try:
        client = _get_manticore_client()

        # query
        where_clause, filters = build_task_query_conditions()

        #  status, default verifying
        if 'status' not in filters:
            if where_clause == "1=1":
                where_clause = "bisect_status = 'verifying'"
            else:
                where_clause = f"bisect_status = 'verifying' AND {where_clause}"
            filters['status'] = 'verifying'

        # statscount
        count_query = f"""
            SELECT COUNT(*) as count
            FROM bisect
            WHERE {where_clause}
        """
        count_result = client.sql_select(count_query)
        count = count_result[0]['count'] if count_result else 0

        if count == 0:
            return jsonify({
                "status": "success",
                "message": "No verifying tasks to reset",
                "reset_count": 0,
                "filters": filters
            }), 200

        # reset
        current_time = int(time.time())
        update_query = f"""
            UPDATE bisect
            SET bisect_status = 'wait',
                updated_at = {current_time},
                submit_time = {current_time}
            WHERE {where_clause}
        """

        client.sql_raw(update_query)

        condition_summary = build_condition_summary(filters)
        logger.info(f"API reset | count: {count} | conditions: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} verifying tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"reset verifying tasks failed: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def reset_pending_verification_tasks():
    """
    resetpending_verification status taskwaitstatus

    supportquery conditions:
    - category: 
    - hours: N
    - git_url: repo
     ( query_builder supportconditions)
    """
    try:
        client = _get_manticore_client()

        # query
        where_clause, filters = build_task_query_conditions()

        #  status, default pending_verification
        if 'status' not in filters:
            if where_clause == "1=1":
                where_clause = "bisect_status = 'pending_verification'"
            else:
                where_clause = f"bisect_status = 'pending_verification' AND {where_clause}"
            filters['status'] = 'pending_verification'

        # statscount
        count_query = f"""
            SELECT COUNT(*) as count
            FROM bisect
            WHERE {where_clause}
        """
        count_result = client.sql_select(count_query)
        count = count_result[0]['count'] if count_result else 0

        if count == 0:
            return jsonify({
                "status": "success",
                "message": "No pending_verification tasks to reset",
                "reset_count": 0,
                "filters": filters
            }), 200

        # reset
        current_time = int(time.time())
        update_query = f"""
            UPDATE bisect
            SET bisect_status = 'wait',
                updated_at = {current_time},
                submit_time = {current_time}
            WHERE {where_clause}
        """

        client.sql_raw(update_query)

        condition_summary = build_condition_summary(filters)
        logger.info(f"API reset | count: {count} | conditions: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} pending_verification tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"reset pending_verification tasks failed: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def cleanup_orphaned_verifying():
    """Reset orphaned verifying tasks (related task failed or missing)."""
    try:
        import json
        client = _get_manticore_client()

        # query verifying-status tasks
        query = """
            SELECT id, j FROM bisect
            WHERE bisect_status = 'verifying'
            LIMIT 10000
            OPTION max_matches=10000
        """

        verifying_tasks = client.sql_select(query)

        if not verifying_tasks:
            return jsonify({
                "status": "success",
                "message": "No verifying tasks found",
                "reset_count": 0
            }), 200

        reset_count = 0
        current_time = int(time.time())

        for task in verifying_tasks:
            try:
                task_id = task.get('id')
                j_field = task.get('j', '{}')

                #  j 
                if isinstance(j_field, str):
                    j_data = json.loads(j_field) if j_field else {}
                else:
                    j_data = j_field

                related_task_id = j_data.get('related_task_id')

                if not related_task_id:
                    # task, reset wait
                    update_query = f"""
                        UPDATE bisect
                        SET bisect_status = 'wait', updated_at = {current_time}, submit_time = {current_time}
                        WHERE id = {task_id}
                    """
                    client.sql_raw(update_query)
                    reset_count += 1
                    logger.info(f"Reset verifying task {task_id} (no related_task_id)")
                    continue

                # check related task status
                related_query = f"""
                    SELECT id, bisect_status FROM bisect
                    WHERE id = {int(related_task_id)}
                    LIMIT 1
                """

                related_result = client.sql_select(related_query)

                # tasknot foundstatus failed, reset wait
                if not related_result:
                    update_query = f"""
                        UPDATE bisect
                        SET bisect_status = 'wait', updated_at = {current_time}, submit_time = {current_time}
                        WHERE id = {task_id}
                    """
                    client.sql_raw(update_query)
                    reset_count += 1
                    logger.info(f"Reset verifying task {task_id} (related task {related_task_id} not found)")
                elif related_result[0].get('bisect_status') == 'failed':
                    update_query = f"""
                        UPDATE bisect
                        SET bisect_status = 'wait', updated_at = {current_time}, submit_time = {current_time}
                        WHERE id = {task_id}
                    """
                    client.sql_raw(update_query)
                    reset_count += 1
                    logger.info(f"Reset verifying task {task_id} (related task {related_task_id} has failed)")

            except Exception as e:
                logger.error(f"verifyingtask {task.get('id')} failed: {str(e)}")
                continue

        logger.info(f"API cleanup | Reset {reset_count} orphaned verifying tasks")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {reset_count} orphaned verifying tasks",
            "reset_count": reset_count,
            "total_verifying_tasks": len(verifying_tasks)
        }), 200

    except Exception as e:
        logger.error(f"cleanup orphaned verifying tasks failed: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500


def test_regression_write():
    """testregression"""
    try:
        # test
        test_task = {
            "error_id": "test.error.regression_write_test",
            "bad_job_id": "test_job_123456"
        }
        test_bad_commit = "abcd1234567890abcdef1234567890abcdef1234"
        
        # 
        success = bisect_task_instance._write_regression_record(test_task, test_bad_commit)
        
        if success:
            return jsonify({
                "status": "success",
                "message": "regressiontestsuccess",
                "test_data": {
                    "error_id": test_task["error_id"],
                    "bad_job_id": test_task["bad_job_id"],
                    "bad_commit": test_bad_commit
                }
            }), 200
        else:
            return jsonify({
                "status": "failed",
                "message": "regressiontestfailed"
            }), 500
            
    except Exception as e:
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def trigger_producer_run():
    """Manually trigger a producer run"""
    try:
        force = request.args.get('force', 'false').lower() == 'true'
        result = bisect_task_instance.trigger_producer_run(force=force)
        if result['status'] == 'success':
            return jsonify(result), 200
        else: # busy
            return jsonify(result), 409 # Conflict
    except Exception as e:
        logger.error(f"Failed to trigger producer run: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def reset_task_by_id():
    """Reset a task by ID to wait status."""
    try:
        task_id = request.args.get('id')

        if not task_id:
            return jsonify({
                "status": "error",
                "error": "Task ID is required"
            }), 400

        # verify(check)
        if not task_id.isdigit():
            return jsonify({
                "status": "error",
                "error": "Invalid task ID format"
            }), 400

        try:
            task_id_int = int(task_id)
            # ManticoreSearch uses 64-bit integers
            if task_id_int <= 0 or task_id_int > Config.MAX_INT64:
                return jsonify({
                    "status": "error",
                    "error": "Task ID out of valid range"
                }), 400
        except ValueError:
            return jsonify({
                "status": "error",
                "error": "Invalid task ID format"
            }), 400

        client = _get_manticore_client()

        # query task status
        check_query = f"SELECT id, bisect_status FROM bisect WHERE id = {task_id_int}"
        result = client.sql_select(check_query)

        if not result or len(result) == 0:
            return jsonify({
                "status": "error",
                "error": f"Task {task_id_int} not found"
            }), 404

        current_status = result[0].get('bisect_status')

        # reset failed,processing  success status tasks
        if current_status not in ['failed', 'processing', 'success']:
            return jsonify({
                "status": "error",
                "error": f"Cannot reset task in '{current_status}' status. Only 'failed', 'processing', or 'success' tasks can be reset.",
                "current_status": current_status
            }), 400

        # taskstatus
        current_time = int(time.time())
        update_query = f"""
            UPDATE bisect
            SET bisect_status = 'wait',
                last_error = '',
                updated_at = {current_time},
                submit_time = {current_time}
            WHERE id = {task_id_int}
        """

        client.sql_raw(update_query)

        logger.info(f"API reset | Task {task_id_int} reset from '{current_status}' to 'wait' status")

        return jsonify({
            "status": "success",
            "message": f"Task {task_id_int} successfully reset to wait status",
            "task_id": task_id_int,
            "previous_status": current_status,
            "new_status": "wait"
        }), 200

    except Exception as e:
        logger.error(f"reset tasks failed: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def reset_tasks_by_condition():
    """
    Reset tasks to wait status by conditions

    supportquery conditions:
    - status: reset by task status
    - error_id: errorIDreset
    - bad_job_id: bad_job_idreset
    - category: reset
    - hours: resetNtask
    - git_url: repoURLreset
    - task_id: resettask
    - task_ids: reset multiple tasks (comma-separated)
    - first_bad_commit: first_bad_commitreset (supportSHA)

    conditions
    """
    try:
        client = _get_manticore_client()

        # query
        where_clause, filters = build_task_query_conditions()

        # conditions
        if not filters:
            return jsonify({
                "status": "error",
                "error": "resetconditions (status, error_id, bad_job_id, category, hours, git_url, task_id, task_ids, first_bad_commit)"
            }), 400

        # statsresetcount
        count_query = f"""
            SELECT COUNT(*) as count
            FROM bisect
            WHERE {where_clause}
        """
        count_result = client.sql_select(count_query)
        count = count_result[0]['count'] if count_result else 0

        if count == 0:
            return jsonify({
                "status": "success",
                "message": "No tasks to reset",
                "reset_count": 0,
                "filters": filters
            }), 200

        # reset
        current_time = int(time.time())
        update_query = f"""
            UPDATE bisect
            SET bisect_status = 'wait',
                last_error = '',
                updated_at = {current_time},
                submit_time = {current_time}
            WHERE {where_clause}
        """

        client.sql_raw(update_query)

        condition_summary = build_condition_summary(filters)
        logger.info(f"API reset | count: {count} | conditions: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"reset tasks failed: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def set_tasks_to_verifying():
    """taskstatus verifying"""
    try:
        data = request.json
        task_ids = data.get('task_ids')

        if not task_ids or not isinstance(task_ids, list):
            return jsonify({
                "status": "error",
                "error": "task_ids (a list of integers) is required"
            }), 400

        # Validate IDs are integers
        validated_ids = []
        for task_id in task_ids:
            try:
                validated_ids.append(int(task_id))
            except (ValueError, TypeError):
                return jsonify({
                    "status": "error",
                    "error": f"Invalid task ID format: {task_id}"
                }), 400
        
        if not validated_ids:
            return jsonify({
                "status": "error",
                "error": "No valid task IDs provided"
            }), 400

        client = _get_manticore_client()
        
        ids_str = ','.join(map(str, validated_ids))
        current_time = int(time.time())

        # taskstatus
        update_query = f"""
            UPDATE bisect
            SET bisect_status = 'verifying',
                updated_at = {current_time},
                submit_time = {current_time}
            WHERE id IN ({ids_str})
        """

        result = client.sql_raw(update_query)
        updated_count = result[0].get('updated', 0) if result and result[0] else 0

        logger.info(f"API call | Set {updated_count} tasks to 'verifying' status. IDs: {ids_str}")

        return jsonify({
            "status": "success",
            "message": f"Successfully set {updated_count} tasks to 'verifying' status.",
            "updated_count": updated_count,
            "task_ids": validated_ids
        }), 200

    except Exception as e:
        logger.error(f"task verificationingfailed: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def delete_tasks_by_condition():
    """
    conditionsdeletetask

    supportquery conditions:
    - status: delete by task status
    - error_id: errorIDdelete
    - bad_job_id: bad_job_iddelete
    - category: delete
    - hours: deleteNtask
    - git_url: repoURLdelete
    - task_id: deletetask
    - task_ids: delete multiple tasks (comma-separated)
    - first_bad_commit: first_bad_commitdelete (supportSHA)

    conditions
    """
    try:
        client = _get_manticore_client()

        # query
        where_clause, filters = build_task_query_conditions()

        # conditions
        if not filters:
            return jsonify({
                "status": "error",
                "error": "deleteconditions (status, error_id, bad_job_id, category, hours, git_url, task_id, task_ids, first_bad_commit)"
            }), 400

        # statsdeletecount
        count_query = f"""
            SELECT COUNT(*) as count
            FROM bisect
            WHERE {where_clause}
        """
        count_result = client.sql_select(count_query)
        count = count_result[0]['count'] if count_result else 0

        if count == 0:
            return jsonify({
                "status": "success",
                "message": "No tasks to delete",
                "deleted_count": 0,
                "filters": filters
            }), 200

        # delete
        delete_query = f"DELETE FROM bisect WHERE {where_clause}"

        condition_summary = build_condition_summary(filters)
        logger.info(f"API delete | count: {count} | conditions: {condition_summary}")

        client.sql_raw(delete_query)

        return jsonify({
            "status": "success",
            "message": f"Successfully deleted {count} tasks",
            "deleted_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"Failed to delete tasks: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

# ==================== Pool Monitoring API Controllers ====================
# Initialize pool monitor service singleton
_pool_monitor = None

def _get_pool_monitor():
    """Get the pool monitor singleton instance."""
    global _pool_monitor
    if _pool_monitor is None:
        _pool_monitor = PoolMonitorService()
    return _pool_monitor

def get_pool_status():
    """Get repository pool status."""
    try:
        monitor = _get_pool_monitor()
        status = monitor.get_pool_status()
        return jsonify(status), 200
    except Exception as e:
        logger.error(f"Failed to get pool status: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def trigger_pool_cleanup():
    """Trigger workspace cleanup"""
    try:
        monitor = _get_pool_monitor()

        dry_run = request.json.get('dry_run', True) if request.json else True
        max_age_days = request.json.get('max_age_days', None) if request.json else None

        result = monitor.check_and_cleanup(
            dry_run=dry_run,
            max_age_days=max_age_days
        )

        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Failed to trigger pool cleanup: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def get_pool_stats():
    """getstats"""
    try:
        monitor = _get_pool_monitor()
        return jsonify(monitor.stats), 200
    except Exception as e:
        logger.error(f"Failed to get pool stats: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def verify_pool_consistency():
    """verify"""
    try:
        monitor = _get_pool_monitor()
        result = monitor.verify_consistency()
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Failed to verify pool consistency: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500


def start_pool_monitor():
    """"""
    try:
        monitor = _get_pool_monitor()
        result = monitor.start_monitor()
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Failed to start pool monitor: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def stop_pool_monitor():
    """"""
    try:
        monitor = _get_pool_monitor()
        result = monitor.stop_monitor()
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Failed to stop pool monitor: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500
