from flask import Blueprint

from .controllers import (
    new_bisect_task,
    list_bisect_tasks,
    reset_failed_tasks,
    reset_processing_tasks,
    reset_verifying_tasks,
    reset_pending_verification_tasks,
    cleanup_orphaned_verifying,
    reset_task_by_id,
    reset_tasks_by_condition,
    thread_pool_status,
    toggle_producer,
    get_producer_status,
    delete_tasks_by_condition,
    trigger_producer_run,
    set_tasks_to_verifying,
    # Pool monitoring controllers
    get_pool_status,
    trigger_pool_cleanup,
    get_pool_stats,
    verify_pool_consistency,
    start_pool_monitor,
    stop_pool_monitor
)

api_bp = Blueprint('api', __name__)

# API路由定义
api_bp.route('/new_bisect_task', methods=['POST'])(new_bisect_task)
api_bp.route('/list_bisect_tasks', methods=['GET'])(list_bisect_tasks)
api_bp.route('/reset_failed_tasks', methods=['DELETE'])(reset_failed_tasks)
api_bp.route('/reset_processing_tasks', methods=['POST'])(reset_processing_tasks)
api_bp.route('/reset_verifying_tasks', methods=['POST'])(reset_verifying_tasks)
api_bp.route('/reset_pending_verification_tasks', methods=['POST'])(reset_pending_verification_tasks)
api_bp.route('/cleanup_orphaned_verifying', methods=['POST'])(cleanup_orphaned_verifying)
api_bp.route('/reset_task', methods=['POST'])(reset_task_by_id)
api_bp.route('/reset_tasks', methods=['POST'])(reset_tasks_by_condition)
api_bp.route('/thread_pool_status', methods=['GET'])(thread_pool_status)
api_bp.route('/toggle_producer', methods=['POST'])(toggle_producer)
api_bp.route('/producer_status', methods=['GET'])(get_producer_status)
api_bp.route('/delete_tasks', methods=['DELETE'])(delete_tasks_by_condition)
api_bp.route('/trigger_producer_run', methods=['POST'])(trigger_producer_run)
api_bp.route('/set_tasks_to_verifying', methods=['POST'])(set_tasks_to_verifying)

# Pool monitoring routes
api_bp.route('/pool/status', methods=['GET'])(get_pool_status)
api_bp.route('/pool/cleanup', methods=['POST'])(trigger_pool_cleanup)
api_bp.route('/pool/stats', methods=['GET'])(get_pool_stats)
api_bp.route('/pool/verify', methods=['POST'])(verify_pool_consistency)
api_bp.route('/pool/monitor/start', methods=['POST'])(start_pool_monitor)
api_bp.route('/pool/monitor/stop', methods=['POST'])(stop_pool_monitor)
