#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
API query conditions
Utilities for list/reset/delete filtering.
"""

import time
from typing import Dict, Any, Optional, List, Tuple
from flask import request
from config import Config


def _escape_sql_string(value: str, escape_wildcards: bool = False) -> str:
    """Escape string for ManticoreSearch SQL queries

    Args:
        value: The string to escape
        escape_wildcards: If True, also escape LIKE wildcards (% and _)

    Returns:
        Escaped string safe for SQL queries
    """
    if value is None:
        return ""
    escaped = value.replace("\\", "\\\\").replace("'", "\\'")
    if escape_wildcards:
        escaped = escaped.replace("%", "\\%").replace("_", "\\_")
    return escaped


def _validate_task_id(task_id: str) -> int:
    """Validate and convert task_id to integer

    Args:
        task_id: Task ID string to validate

    Returns:
        Validated task ID as integer

    Raises:
        ValueError: If task_id is invalid
    """
    if not task_id or not task_id.strip().isdigit():
        raise ValueError(f"Invalid task_id format: {task_id}")
    task_id_int = int(task_id.strip())
    if task_id_int <= 0 or task_id_int > Config.MAX_INT64:
        raise ValueError(f"task_id out of valid range: {task_id_int}")
    return task_id_int


def build_task_query_conditions() -> Tuple[str, Dict[str, Any]]:
    """
    Build task query conditions from Flask request parameters.

    Supported query params:
    - status: task status (wait/processing/success/failed/verifying/pending_verification)
    - error_id: exact error ID
    - bad_job_id: exact bad_job_id
    - category: task category (functional/performance/build)
    - hours: tasks within last N hours
    - git_url: fuzzy match on repository URL
    - task_id: single task ID
    - task_ids: multiple task IDs (comma-separated)
    - first_bad_commit: full or short SHA

    Returns:
        (where_clause, filters) tuple
    """
    conditions = []
    filters = {}

    # task status
    status = request.args.get('status')
    if status:
        status_escaped = _escape_sql_string(status)
        conditions.append(f"bisect_status = '{status_escaped}'")
        filters['status'] = status

    # error ID
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

    # 
    category = request.args.get('category')
    if category:
        category_escaped = _escape_sql_string(category)
        conditions.append(f"category = '{category_escaped}'")
        filters['category'] = category

    # hours - last N hours
    hours = request.args.get('hours')
    if hours:
        try:
            hours_int = int(hours)
            cutoff_time = int(time.time()) - (hours_int * 3600)
            conditions.append(f"updated_at >= {cutoff_time}")
            filters['hours'] = hours_int
        except ValueError:
            pass  # ignore invalid hours input

    # git_url - fuzzy match
    git_url = request.args.get('git_url')
    if git_url:
        git_url_escaped = _escape_sql_string(git_url)
        conditions.append(f"git_url LIKE '%{git_url_escaped}%'")
        filters['git_url'] = git_url

    # first_bad_commit - exact/full/short SHA
    first_bad_commit = request.args.get('first_bad_commit')
    if first_bad_commit:
        commit_escaped = _escape_sql_string(first_bad_commit)
        conditions.append(f"first_bad_commit = '{commit_escaped}'")
        filters['first_bad_commit'] = first_bad_commit

    # task ID (with validation)
    task_id = request.args.get('task_id')
    if task_id:
        task_id_int = _validate_task_id(task_id)
        conditions.append(f"id = {task_id_int}")
        filters['task_id'] = task_id_int

    # task IDs (comma-separated, with validation)
    task_ids = request.args.get('task_ids')
    if task_ids:
        validated_ids = []
        for tid in task_ids.split(','):
            validated_ids.append(_validate_task_id(tid))
        ids_str = ','.join(str(tid) for tid in validated_ids)
        conditions.append(f"id IN ({ids_str})")
        filters['task_ids'] = validated_ids

    # Build WHERE clause
    where_clause = " AND ".join(conditions) if conditions else "1=1"

    return where_clause, filters


def build_condition_summary(filters: Dict[str, Any]) -> str:
    """
    Build a concise condition summary for logs.

    Args:
        filters: conditions dict

    Returns:
        summary string
    """
    if not filters:
        return "all_tasks"

    parts = []
    for key, value in filters.items():
        if key == 'error_id' and isinstance(value, str) and len(value) > 30:
            parts.append(f"{key}={value[:30]}...")
        elif key == 'git_url' and isinstance(value, str) and len(value) > 30:
            parts.append(f"{key}={value[:30]}...")
        elif key == 'first_bad_commit':
            # Trim commit SHA for concise logging
            commit_display = value[:12] if len(value) > 12 else value
            parts.append(f"commit={commit_display}")
        elif key == 'hours':
            parts.append(f"hours={value}")
        elif key == 'task_ids':
            parts.append(f"task_ids={len(value)}")
        else:
            parts.append(f"{key}={value}")

    return ", ".join(parts)
