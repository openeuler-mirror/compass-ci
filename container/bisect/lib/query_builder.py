#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
API 查询条件构建器
用于 list/reset/delete 等操作的统一条件构建
"""

import time
from typing import Dict, Any, Optional, List, Tuple
from flask import request


def _escape_sql_string(value: str) -> str:
    """Escape string for ManticoreSearch SQL queries"""
    if value is None:
        return ""
    return value.replace("\\", "\\\\").replace("'", "\\'")


def build_task_query_conditions() -> Tuple[str, Dict[str, Any]]:
    """
    从 Flask request 构建任务查询条件

    支持的查询参数:
    - status: 任务状态 (wait/processing/success/failed/verifying/pending_verification)
    - error_id: 错误ID (精确匹配)
    - bad_job_id: bad_job_id (精确匹配)
    - category: 类别 (functional/performance/build)
    - hours: 最近N小时内的任务
    - git_url: 仓库URL (模糊匹配)
    - task_id: 单个任务ID
    - task_ids: 多个任务ID (逗号分隔)
    - first_bad_commit: 按first_bad_commit筛选 (精确匹配，完整40字符SHA)

    Returns:
        (where_clause, filters) - WHERE 子句和过滤条件字典
    """
    conditions = []
    filters = {}

    # 任务状态
    status = request.args.get('status')
    if status:
        status_escaped = _escape_sql_string(status)
        conditions.append(f"bisect_status = '{status_escaped}'")
        filters['status'] = status

    # 错误ID
    error_id = request.args.get('error_id')
    if error_id:
        error_id_escaped = _escape_sql_string(error_id)
        conditions.append(f"error_id = '{error_id_escaped}'")
        filters['error_id'] = error_id

    # bad_job_id
    bad_job_id = request.args.get('bad_job_id')
    if bad_job_id:
        bad_job_id_escaped = _escape_sql_string(bad_job_id)
        conditions.append(f"bad_job_id = '{bad_job_id_escaped}'")
        filters['bad_job_id'] = bad_job_id

    # 类别
    category = request.args.get('category')
    if category:
        category_escaped = _escape_sql_string(category)
        conditions.append(f"category = '{category_escaped}'")
        filters['category'] = category

    # 时间范围 - 最近N小时
    hours = request.args.get('hours')
    if hours:
        try:
            hours_int = int(hours)
            cutoff_time = int(time.time()) - (hours_int * 3600)
            conditions.append(f"submit_time >= {cutoff_time}")
            filters['hours'] = hours_int
        except ValueError:
            pass  # 忽略无效的 hours 参数

    # git_url - 模糊匹配
    git_url = request.args.get('git_url')
    if git_url:
        git_url_escaped = _escape_sql_string(git_url)
        conditions.append(f"git_url LIKE '%{git_url_escaped}%'")
        filters['git_url'] = git_url

    # first_bad_commit - 精确匹配
    first_bad_commit = request.args.get('first_bad_commit')
    if first_bad_commit:
        commit_escaped = _escape_sql_string(first_bad_commit)
        conditions.append(f"first_bad_commit = '{commit_escaped}'")
        filters['first_bad_commit'] = first_bad_commit

    # 单个任务ID
    task_id = request.args.get('task_id')
    if task_id:
        conditions.append(f"id = {task_id}")
        filters['task_id'] = task_id

    # 多个任务ID (逗号分隔)
    task_ids = request.args.get('task_ids')
    if task_ids:
        ids_list = [tid.strip() for tid in task_ids.split(',')]
        ids_str = ','.join(ids_list)
        conditions.append(f"id IN ({ids_str})")
        filters['task_ids'] = ids_list

    # 构建 WHERE 子句
    where_clause = " AND ".join(conditions) if conditions else "1=1"

    return where_clause, filters


def build_condition_summary(filters: Dict[str, Any]) -> str:
    """
    构建条件摘要（用于日志和用户提示）

    Args:
        filters: 过滤条件字典

    Returns:
        条件描述字符串
    """
    if not filters:
        return "所有任务"

    parts = []
    for key, value in filters.items():
        if key == 'error_id' and isinstance(value, str) and len(value) > 30:
            parts.append(f"{key}={value[:30]}...")
        elif key == 'git_url' and isinstance(value, str) and len(value) > 30:
            parts.append(f"{key}包含{value[:30]}...")
        elif key == 'first_bad_commit':
            # 显示 commit SHA（完整或短）
            commit_display = value[:12] if len(value) > 12 else value
            parts.append(f"commit={commit_display}")
        elif key == 'hours':
            parts.append(f"最近{value}小时")
        elif key == 'task_ids':
            parts.append(f"{len(value)}个指定任务")
        else:
            parts.append(f"{key}={value}")

    return ", ".join(parts)
