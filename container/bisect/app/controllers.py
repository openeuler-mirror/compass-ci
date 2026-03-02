import sys
import os
import time
import traceback
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
    """获取ManticoreSearch HTTP客户端"""
    return ManticoreClient(
        host=os.environ.get('MANTICORE_HOST', 'localhost'),
        port=int(os.environ.get('MANTICORE_WRITE_PORT', '9308'))
    )

def new_bisect_task():
    try:
        task_data = request.json
        if not task_data:
            raise ValueError("No task data provided")
            
        # API层验证 - 确保 j 字段不为 null
        if 'j' in task_data and task_data['j'] is None:
            logger.warning("API请求包含无效的 null j 字段，已清理")
            task_data['j'] = {}
            
        logger.debug(f"DEBUG - Controller received request | Data: {task_data}")
            
        result = bisect_task_instance.add_bisect_task(task_data, priority=999)
            
        logger.debug(f"DEBUG - Controller operation result: {result}")
        
        # 处理新的返回格式
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
                    "code": 409,  # Conflict - 资源已存在
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
            # 兼容旧的布尔返回值
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
    """
    列出bisect任务，支持多种筛选条件

    查询参数:
    - status: 按任务状态筛选 (wait/processing/success/failed/verifying/pending_verification)
    - error_id: 按错误ID筛选 (精确匹配)
    - bad_job_id: 按bad_job_id筛选
    - category: 按类别筛选 (functional/performance/build)
    - hours: 最近N小时内的任务
    - git_url: 按仓库URL筛选 (模糊匹配)
    - task_id: 单个任务ID
    - task_ids: 多个任务ID (逗号分隔)
    - first_bad_commit: 按first_bad_commit筛选 (精确匹配)
    - limit: 限制返回结果数量 (默认 Config.DEFAULT_QUERY_LIMIT)
    """
    try:
        client = _get_manticore_client()

        # 使用公共查询构建器
        where_clause, filters = build_task_query_conditions()

        # 获取 limit 参数
        limit = request.args.get('limit', str(Config.DEFAULT_QUERY_LIMIT))
        try:
            limit = int(limit)
            limit = max(1, min(limit, Config.MAX_QUERY_LIMIT))
        except ValueError:
            limit = Config.DEFAULT_QUERY_LIMIT

        # 构建 SQL 查询
        sql_query = f"""
            SELECT id, * FROM bisect
            WHERE {where_clause}
            ORDER BY id DESC
            LIMIT {limit}
            OPTION max_matches={limit}
        """

        logger.debug(f"执行查询: {sql_query}")
        tasks = client.sql_select(sql_query)

        # 返回结果
        result_count = len(tasks) if tasks else 0

        return jsonify({
            "tasks": tasks or [],
            "count": result_count,
            "filters": filters,
            "limit": limit
        }), 200
    except Exception as e:
        logger.error(f"Error listing bisect tasks: {str(e)}")
        return jsonify({"error": str(e)}), 500



def thread_pool_status():
    """获取线程池状态"""
    try:
        # Python 3.11兼容性修复：_tasks_done可能不存在
        completed_tasks = 0
        try:
            completed_tasks = bisect_task_instance.thread_pool._work_queue._tasks_done
        except AttributeError:
            # Python 3.11+ 中 SimpleQueue 没有 _tasks_done 属性
            completed_tasks = "Not available (Python 3.11+)"
        
        status = {
            "max_workers": bisect_task_instance.thread_pool._max_workers,
            "active_threads": threading.active_count() - 1,  # 排除主线程
            "pending_tasks": bisect_task_instance.thread_pool._work_queue.qsize(),
            "completed_tasks": completed_tasks
        }
        return jsonify(status), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def toggle_producer():
    """动态切换生产者状态"""
    try:
        state = request.args.get('state')
        if state not in ['enable', 'disable']:
            return jsonify({"error": "Invalid state. Use 'enable' or 'disable'"}), 400
        
        old_state = Config.BISECT_PRODUCER_ENABLED
        Config.BISECT_PRODUCER_ENABLED = (state == 'enable')
        
        # 如果从禁用切换到启用，且生产者线程不存在，需要启动新线程
        if not old_state and Config.BISECT_PRODUCER_ENABLED:
            # 检查是否已有生产者线程运行
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
                # 启动新的生产者线程
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
    """获取生产者状态"""
    try:
        # 检查配置状态
        config_enabled = Config.BISECT_PRODUCER_ENABLED
        
        # 检查是否有生产者线程在运行
        producer_threads = []
        for thread in threading.enumerate():
            is_producer = False
            
            # 检查线程目标函数名
            if hasattr(thread, '_target') and thread._target:
                if 'bisect_producer' in str(thread._target.__name__ if hasattr(thread._target, '__name__') else thread._target):
                    is_producer = True
            
            # 检查线程名称
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
    重置processing状态的任务为wait状态

    支持额外的查询条件:
    - category: 按类别筛选
    - hours: 最近N小时
    - git_url: 按仓库筛选
    等等 (所有 query_builder 支持的条件)
    """
    try:
        client = _get_manticore_client()

        # 使用公共查询构建器
        where_clause, filters = build_task_query_conditions()

        # 如果没有指定 status，默认为 processing
        if 'status' not in filters:
            if where_clause == "1=1":
                where_clause = "bisect_status = 'processing'"
            else:
                where_clause = f"bisect_status = 'processing' AND {where_clause}"
            filters['status'] = 'processing'

        # 统计数量
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

        # 执行重置
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
        logger.info(f"API reset | 数量: {count} | 条件: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} processing tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"重置processing任务失败: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def reset_failed_tasks():
    """
    重置failed状态的任务为wait状态

    支持额外的查询条件:
    - category: 按类别筛选
    - hours: 最近N小时
    - git_url: 按仓库筛选
    等等 (所有 query_builder 支持的条件)
    """
    try:
        client = _get_manticore_client()

        # 使用公共查询构建器
        where_clause, filters = build_task_query_conditions()

        # 如果没有指定 status，默认为 failed
        if 'status' not in filters:
            if where_clause == "1=1":
                where_clause = "bisect_status = 'failed'"
            else:
                where_clause = f"bisect_status = 'failed' AND {where_clause}"
            filters['status'] = 'failed'

        # 统计数量
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

        # 执行重置 (清空 last_error)
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
        logger.info(f"API reset | 数量: {count} | 条件: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} failed tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"重置failed任务失败: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def reset_verifying_tasks():
    """
    重置verifying状态的任务为wait状态

    支持额外的查询条件:
    - category: 按类别筛选
    - hours: 最近N小时
    - git_url: 按仓库筛选
    等等 (所有 query_builder 支持的条件)
    """
    try:
        client = _get_manticore_client()

        # 使用公共查询构建器
        where_clause, filters = build_task_query_conditions()

        # 如果没有指定 status，默认为 verifying
        if 'status' not in filters:
            if where_clause == "1=1":
                where_clause = "bisect_status = 'verifying'"
            else:
                where_clause = f"bisect_status = 'verifying' AND {where_clause}"
            filters['status'] = 'verifying'

        # 统计数量
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

        # 执行重置
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
        logger.info(f"API reset | 数量: {count} | 条件: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} verifying tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"重置verifying任务失败: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def reset_pending_verification_tasks():
    """
    重置pending_verification状态的任务为wait状态

    支持额外的查询条件:
    - category: 按类别筛选
    - hours: 最近N小时
    - git_url: 按仓库筛选
    等等 (所有 query_builder 支持的条件)
    """
    try:
        client = _get_manticore_client()

        # 使用公共查询构建器
        where_clause, filters = build_task_query_conditions()

        # 如果没有指定 status，默认为 pending_verification
        if 'status' not in filters:
            if where_clause == "1=1":
                where_clause = "bisect_status = 'pending_verification'"
            else:
                where_clause = f"bisect_status = 'pending_verification' AND {where_clause}"
            filters['status'] = 'pending_verification'

        # 统计数量
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

        # 执行重置
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
        logger.info(f"API reset | 数量: {count} | 条件: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} pending_verification tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"重置pending_verification任务失败: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def cleanup_orphaned_verifying():
    """清理孤立的verifying任务（关联任务已失败或不存在）"""
    try:
        import json
        client = _get_manticore_client()

        # 查询所有verifying状态的任务
        query = """
            SELECT id, j FROM bisect
            WHERE bisect_status = 'verifying'
            LIMIT 10000
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

                # 解析 j 字段
                if isinstance(j_field, str):
                    j_data = json.loads(j_field) if j_field else {}
                else:
                    j_data = j_field

                related_task_id = j_data.get('related_task_id')

                if not related_task_id:
                    # 没有关联任务，重置为 wait
                    update_query = f"""
                        UPDATE bisect
                        SET bisect_status = 'wait', updated_at = {current_time}, submit_time = {current_time}
                        WHERE id = {task_id}
                    """
                    client.sql_raw(update_query)
                    reset_count += 1
                    logger.info(f"Reset verifying task {task_id} (no related_task_id)")
                    continue

                # 检查关联任务状态
                related_query = f"""
                    SELECT id, bisect_status FROM bisect
                    WHERE id = {int(related_task_id)}
                    LIMIT 1
                """

                related_result = client.sql_select(related_query)

                # 如果关联任务不存在或状态为 failed，重置为 wait
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
                logger.error(f"处理verifying任务 {task.get('id')} 失败: {str(e)}")
                continue

        logger.info(f"API cleanup | Reset {reset_count} orphaned verifying tasks")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {reset_count} orphaned verifying tasks",
            "reset_count": reset_count,
            "total_verifying_tasks": len(verifying_tasks)
        }), 200

    except Exception as e:
        logger.error(f"清理孤立verifying任务失败: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500


def test_regression_write():
    """测试regression写入功能"""
    try:
        # 模拟测试数据
        test_task = {
            "error_id": "test.error.regression_write_test",
            "bad_job_id": "test_job_123456"
        }
        test_bad_commit = "abcd1234567890abcdef1234567890abcdef1234"
        
        # 调用写入功能
        success = bisect_task_instance._write_regression_record(test_task, test_bad_commit)
        
        if success:
            return jsonify({
                "status": "success",
                "message": "regression写入测试成功",
                "test_data": {
                    "error_id": test_task["error_id"],
                    "bad_job_id": test_task["bad_job_id"],
                    "bad_commit": test_bad_commit
                }
            }), 200
        else:
            return jsonify({
                "status": "failed",
                "message": "regression写入测试失败"
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
    """重置指定ID的任务为wait状态"""
    try:
        task_id = request.args.get('id')

        if not task_id:
            return jsonify({
                "status": "error",
                "error": "Task ID is required"
            }), 400

        # 严格的整数验证（包括范围检查）
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

        # 查询任务当前状态
        check_query = f"SELECT id, bisect_status FROM bisect WHERE id = {task_id_int}"
        result = client.sql_select(check_query)

        if not result or len(result) == 0:
            return jsonify({
                "status": "error",
                "error": f"Task {task_id_int} not found"
            }), 404

        current_status = result[0].get('bisect_status')

        # 允许重置 failed、processing 或 success 状态的任务
        if current_status not in ['failed', 'processing', 'success']:
            return jsonify({
                "status": "error",
                "error": f"Cannot reset task in '{current_status}' status. Only 'failed', 'processing', or 'success' tasks can be reset.",
                "current_status": current_status
            }), 400

        # 更新任务状态
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
        logger.error(f"重置任务失败: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def reset_tasks_by_condition():
    """
    根据条件重置任务为wait状态

    支持的查询条件:
    - status: 按任务状态重置
    - error_id: 按错误ID重置
    - bad_job_id: 按bad_job_id重置
    - category: 按类别重置
    - hours: 重置最近N小时的任务
    - git_url: 按仓库URL重置
    - task_id: 重置单个任务
    - task_ids: 重置多个任务 (逗号分隔)
    - first_bad_commit: 按first_bad_commit重置 (支持完整或短SHA)

    至少需要提供一个条件
    """
    try:
        client = _get_manticore_client()

        # 使用公共查询构建器
        where_clause, filters = build_task_query_conditions()

        # 必须提供至少一个条件
        if not filters:
            return jsonify({
                "status": "error",
                "error": "至少需要提供一个重置条件 (status, error_id, bad_job_id, category, hours, git_url, task_id, task_ids, first_bad_commit)"
            }), 400

        # 统计将要重置的数量
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

        # 执行重置
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
        logger.info(f"API reset | 数量: {count} | 条件: {condition_summary}")

        return jsonify({
            "status": "success",
            "message": f"Successfully reset {count} tasks",
            "reset_count": count,
            "filters": filters
        }), 200

    except Exception as e:
        logger.error(f"重置任务失败: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def set_tasks_to_verifying():
    """手动设置一个或多个任务的状态为 verifying"""
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

        # 更新任务状态
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
        logger.error(f"设置任务为verifying失败: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

def delete_tasks_by_condition():
    """
    根据条件删除任务

    支持的查询条件:
    - status: 按任务状态删除
    - error_id: 按错误ID删除
    - bad_job_id: 按bad_job_id删除
    - category: 按类别删除
    - hours: 删除最近N小时的任务
    - git_url: 按仓库URL删除
    - task_id: 删除单个任务
    - task_ids: 删除多个任务 (逗号分隔)
    - first_bad_commit: 按first_bad_commit删除 (支持完整或短SHA)

    至少需要提供一个条件
    """
    try:
        client = _get_manticore_client()

        # 使用公共查询构建器
        where_clause, filters = build_task_query_conditions()

        # 必须提供至少一个条件
        if not filters:
            return jsonify({
                "status": "error",
                "error": "至少需要提供一个删除条件 (status, error_id, bad_job_id, category, hours, git_url, task_id, task_ids, first_bad_commit)"
            }), 400

        # 统计将要删除的数量
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

        # 执行删除
        delete_query = f"DELETE FROM bisect WHERE {where_clause}"

        condition_summary = build_condition_summary(filters)
        logger.info(f"API delete | 数量: {count} | 条件: {condition_summary}")

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
    """获取池监控服务实例（单例）"""
    global _pool_monitor
    if _pool_monitor is None:
        _pool_monitor = PoolMonitorService()
    return _pool_monitor

def get_pool_status():
    """获取仓库池状态"""
    try:
        monitor = _get_pool_monitor()
        status = monitor.get_pool_status()
        return jsonify(status), 200
    except Exception as e:
        logger.error(f"Failed to get pool status: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def trigger_pool_cleanup():
    """触发仓库池清理"""
    try:
        monitor = _get_pool_monitor()

        # 从请求参数获取选项
        dry_run = request.json.get('dry_run', True) if request.json else True
        max_hours = request.json.get('max_hours', None) if request.json else None

        result = monitor.check_and_cleanup(
            dry_run=dry_run,
            max_hours=max_hours,
            auto_cleanup=True
        )

        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Failed to trigger pool cleanup: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def get_pool_stats():
    """获取池监控统计信息"""
    try:
        monitor = _get_pool_monitor()
        return jsonify(monitor.stats), 200
    except Exception as e:
        logger.error(f"Failed to get pool stats: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def verify_pool_consistency():
    """验证池一致性"""
    try:
        monitor = _get_pool_monitor()
        result = monitor.verify_consistency()
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Failed to verify pool consistency: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def get_repo_instances(repo_name):
    """获取特定仓库的实例信息"""
    try:
        monitor = _get_pool_monitor()
        result = monitor.get_instance_info(repo_name)

        if result['status'] == 'error':
            return jsonify(result), 404
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Failed to get repo instances: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def start_pool_monitor():
    """启动池监控线程"""
    try:
        monitor = _get_pool_monitor()
        result = monitor.start_monitor()
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Failed to start pool monitor: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

def stop_pool_monitor():
    """停止池监控线程"""
    try:
        monitor = _get_pool_monitor()
        result = monitor.stop_monitor()
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Failed to stop pool monitor: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500
