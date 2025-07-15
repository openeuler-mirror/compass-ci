from flask import Blueprint
from app.controllers import (
    new_bisect_task,
    list_bisect_tasks,
    list_tasks_by_status,
    delete_failed_tasks
)

api_bp = Blueprint('api', __name__)

api_bp.route('/new_bisect_task', methods=['POST'])(new_bisect_task)
api_bp.route('/list_bisect_tasks', methods=['GET'])(list_bisect_tasks)
api_bp.route('/list_tasks_by_status', methods=['GET'])(list_tasks_by_status)
api_bp.route('/delete_failed_tasks', methods=['DELETE'])(delete_failed_tasks)
