from flask import Blueprint

from controllers import (
    new_bisect_task,
    list_bisect_tasks,
    delete_failed_tasks
)

api_bp = Blueprint('api', __name__)

# API路由定义
api_bp.route('/new_bisect_task', methods=['POST'])(new_bisect_task)
api_bp.route('/list_bisect_tasks', methods=['GET'])(list_bisect_tasks)
api_bp.route('/delete_failed_tasks', methods=['DELETE'])(delete_failed_tasks)
