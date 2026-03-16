#!/usr/bin/env python3
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2024 Huawei Technologies Co., Ltd. All rights reserved.
"""
Bisect shared utility functions module
Extracted shared code from task_processor.py and bisect_producer.py
"""

import os
import re
import json
import traceback
import subprocess
import shutil
import hashlib
import time
from typing import Dict, List, Any, Optional, Tuple
from pathlib import Path
from collections import defaultdict
from datetime import datetime

# Import logging system
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lib'))
from log_config import logger
from config import Config

def _generate_task_id(bad_job_id, task_identifier):
    """Generate deterministic ID based on task_identifier

    For error_id tasks: ID based only on error_id (same error_id = same task)
    For bisect_metric tasks: ID based on (bad_job_id, bisect_metric)

    task_identifier format: "error_id='xxx'" or "bisect_metric='xxx'"

    Returns:
        19-digit positive integer ID (1000000000000000000 ~ 9223372036854775807)
    """
    if task_identifier.startswith("error_id="):
        # error_id task: use only error_id to generate ID, ensure one task per error_id
        unique_str = task_identifier
    else:
        # bisect_metric task: use (bad_job_id, bisect_metric) to generate ID
        unique_str = f"{bad_job_id}|{task_identifier}"

    hash_bytes = hashlib.sha256(unique_str.encode()).digest()
    hash_int = int.from_bytes(hash_bytes[:8], byteorder='big')

    # Ensure ID is 19 digits:
    # - min: 1000000000000000000 (10^18)
    # - max: 9223372036854775807 (2^63 - 1, signed int64 max)
    # Use modulo to map hash to this range
    min_id = 1000000000000000000  # 10^18
    max_id = 9223372036854775807  # 2^63 - 1
    id_range = max_id - min_id + 1

    return min_id + (hash_int % id_range)

def _create_task_document(validated_data: dict) -> dict:
    """Creates the initial task document from validated data."""
    if validated_data.get("error_id"):
        task_doc = {
            "bad_job_id": validated_data["bad_job_id"],
            "error_id": validated_data["error_id"],
            "bisect_status": "wait",
            "submit_time": int(time.time())
        }
        # Save good_commit to j field (table schema has no good_commit column)
        if validated_data.get("good_commit"):
            task_doc["j"] = {"good_commit": validated_data["good_commit"]}
    else:
        task_doc = {
            "bad_job_id": validated_data["bad_job_id"],
            "bisect_metric": validated_data["bisect_metric"],
            "bisect_status": "wait",
            "submit_time": int(time.time())
        }
        # Save good_commit to j field (table schema has no good_commit column)
        if validated_data.get("good_commit"):
            task_doc["j"] = {"good_commit": validated_data["good_commit"]}

    return task_doc

def smart_split_error_ids(errid_string: str) -> List[str]:
    """
    Smart split error_id string, keeping quoted content intact
    Handles strings like:
    "error1 error2:'quoted_content'has_member error3"
    """
    if not errid_string or not isinstance(errid_string, str):
        return []

    result = []
    current = ""
    in_quotes = False
    quote_char = None

    i = 0
    while i < len(errid_string):
        char = errid_string[i]

        # Handle quote state
        if char in ["'", '"'] and not in_quotes:
            # Start quote
            in_quotes = True
            quote_char = char
            current += char
        elif char == quote_char and in_quotes:
            # End quote
            in_quotes = False
            quote_char = None
            current += char
        elif char == ' ' and not in_quotes:
            # Space separation (only outside quotes)
            if current.strip():
                result.append(current.strip())
            current = ""
        else:
            current += char

        i += 1

    # Add last part
    if current.strip():
        result.append(current.strip())

    # Debug logging
    if len(result) > 1:
        logger.debug(f"Smart split result: {len(result)} parts")
        for idx, part in enumerate(result[:3]):  # Only show first 3
            logger.debug(f"  {idx+1}: {part[:100]}...")

    return result


def extract_git_url_from_full_text_kv(full_text_kv: str) -> str:
    """Extract complete Git repository URL from full_text_kv"""
    if not full_text_kv:
        logger.warning("full_text_kv is empty")
        return None

    try:
        logger.debug(f"Trying to extract git_url from full_text_kv | length: {len(full_text_kv)} | first_100_chars: {full_text_kv[:100]}...")

        # Find ss.linux._url= or pp.makepkg._url= patterns
        url_pattern = r'(?:ss\.linux\._url|pp\.makepkg\._url)=([^\s]+)'
        url_match = re.search(url_pattern, full_text_kv)

        if url_match:
            url = url_match.group(1)
            logger.debug(f"Successfully matched git_url | raw_url: {url}")

            # Standardize URL format
            original_url = url
            if url.startswith("git+http"):
                url = url.replace("git+", "", 1)

            if url != original_url:
                logger.debug(f"URL normalized | original: {original_url} | normalized: {url}")

            return url
        else:
            # Try broader matching
            git_patterns = [
                r'(\w+\._url)=([^\s]+git[^\s]*)',  # Any URL field containing git
                r'(git[^\s]*?)=([^\s]+)',          # Any field starting with git
                r'_url=([^\s]*git[^\s]*)',         # Any _url field containing git
            ]

            for i, pattern in enumerate(git_patterns):
                matches = re.findall(pattern, full_text_kv)
                if matches:
                    logger.debug(f"Alternate pattern {i+1} found matches: {matches[:3]}")  # Only show first 3

            logger.debug(f"No matching git_url pattern found | full_text_kv_sample: {full_text_kv[:200]}...")
            return None

    except Exception as e:
        logger.error(f"Error extracting git_url: {e}")
        logger.debug(f"Exception details: {traceback.format_exc()}")
        return None


def extract_commit_from_full_text_kv(full_text_kv: str) -> str:
    """Extract commit hash or tag from full_text_kv

    Args:
        full_text_kv: full_text_kv field from jobs table

    Returns:
        Commit hash or tag, empty string if not found

    Supported formats:
        - commit: abc123... (40-char full hash)
        - commit: abc123 (12+ char short hash)
        - commit: v6.17 (tag format)
        - head/HEAD: ...
    """
    if not full_text_kv:
        return ''

    try:
        # Match commit hash first (more precise)
        hash_patterns = [
            r'commit[:=]\s*([a-f0-9]{40})',          # commit: abc123... (full 40-char)
            r'commit[:=]\s*([a-f0-9]{12,})',         # commit: abc123 (12+ chars)
            r'head[:=]\s*([a-f0-9]{40})',            # head: abc123...
            r'HEAD[:=]\s*([a-f0-9]{40})',            # HEAD: abc123...
        ]

        for pattern in hash_patterns:
            match = re.search(pattern, full_text_kv, re.IGNORECASE)
            if match:
                commit_hash = match.group(1)
                logger.debug(f"Successfully extracted commit hash | hash: {commit_hash[:12]}...")
                return commit_hash

        # Match tag format (version with or without v prefix)
        tag_patterns = [
            r'commit[:=]\s*(v\d+\.\d+(?:\.\d+)?(?:-rc\d+)?(?:-[\w.]+)?)\b',  # v6.17, v5.10-rc1, v6.12-openeuler
            r'commit[:=]\s*(v\d+\.\d+[^\s,]*)',                               # v6.17-xxx looser match
            r'commit[:=]\s*(\d+\.\d+\.\d+[-.\w]*)',                           # 6.6.0-132.0.0 (no v prefix, openEuler style)
        ]

        for pattern in tag_patterns:
            match = re.search(pattern, full_text_kv, re.IGNORECASE)
            if match:
                tag = match.group(1)
                logger.debug(f"Successfully extracted commit tag | tag: {tag}")
                return tag

        logger.debug("Commit hash or tag not found")
        return ''

    except Exception as e:
        logger.error(f"Error extracting commit: {e}")
        return ''


def get_repo_info_from_job_data(bad_job_id: str, job_data_list: List[Dict]) -> Dict[str, str]:
    """Get repository info from job_data_list"""
    try:
        # Find corresponding job data
        job_data = None
        for item in job_data_list:
            if str(item.get('id')) == str(bad_job_id):
                job_data = item
                break

        if not job_data:
            return {'repo_name': 'unknown', 'git_url': '', 'commit_sample': ''}

        # Extract git_url
        git_url = extract_git_url_from_full_text_kv(job_data.get('full_text_kv', ''))

        # Use extract_repo_name_from_url from this module
        repo_name = extract_repo_name_from_url(git_url) if git_url else 'unknown'

        # Try to extract commit info (simplified, first 8 chars)
        full_text_kv = job_data.get('full_text_kv', '')
        commit_sample = ''
        commit_match = re.search(r'commit=([a-f0-9]{8,})', full_text_kv)
        if commit_match:
            commit_sample = commit_match.group(1)[:8]

        return {
            'repo_name': repo_name,
            'git_url': git_url or '',
            'commit_sample': commit_sample
        }

    except Exception as e:
        logger.debug(f"Failed to get repo info: {str(e)}")
        return {'repo_name': 'unknown', 'git_url': '', 'commit_sample': ''}


def write_analysis_files(job_data_list: List[Dict],
                         filtered_results: Dict,
                         unfiltered_jobs: List[Dict]) -> None:
    """Write analysis results to files for manual review, grouped by error ID"""
    try:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        # Create analysis file directory
        analysis_dir = Path(os.environ.get('RESULT_DIR', '/result/bisect')) / 'logs' / 'analysis'
        analysis_dir.mkdir(exist_ok=True, parents=True)

        # 1. Record filtered tasks (successfully filtered), grouped by error ID
        filtered_file = analysis_dir / f'filtered_jobs_{timestamp}.json'
        filtered_by_errid = defaultdict(list)  # errid -> [task_info, ...]

        for bad_job_id, selected_errids in filtered_results.items():
            # Get repository info
            repo_info = get_repo_info_from_job_data(bad_job_id, job_data_list)

            for errid, analysis in selected_errids:
                filtered_by_errid[errid].append({
                    'bad_job_id': bad_job_id,
                    'priority': getattr(analysis, 'priority', 0),
                    'error_type': getattr(analysis, 'error_type', 'unknown'),
                    'reasons': getattr(analysis, 'reasons', []),
                    'file_paths': getattr(analysis, 'file_paths', []),
                    'flags': getattr(analysis, 'flags', {}),
                    'repo_name': repo_info.get('repo_name', 'unknown'),
                    'git_url': repo_info.get('git_url', ''),
                    'commit_sample': repo_info.get('commit_sample', '')
                })

        # Write grouped by error ID
        filtered_grouped_data = {}
        for errid, tasks in filtered_by_errid.items():
            # Group by repository
            by_repo = defaultdict(list)
            for task in tasks:
                repo_key = f"{task['repo_name']} @ {task['commit_sample']}" if task['commit_sample'] else task['repo_name']
                by_repo[repo_key].append(task['bad_job_id'])

            filtered_grouped_data[errid] = {
                'total_tasks': len(tasks),
                'priority': tasks[0]['priority'],  # Same errid shares priority
                'error_type': tasks[0]['error_type'],
                'reasons': tasks[0]['reasons'],
                'file_paths': tasks[0]['file_paths'],
                'flags': tasks[0]['flags'],
                'by_repository': dict(by_repo),
                'timestamp': timestamp
            }

        with open(filtered_file, 'w', encoding='utf-8') as f:
            json.dump(filtered_grouped_data, f, ensure_ascii=False, indent=2)

        logger.info(f"Filtered results file written | path: {filtered_file} | error_id_types: {len(filtered_grouped_data)}")

        # 2. Record tasks not smart-filtered, grouped by reason and error ID
        unfiltered_file = analysis_dir / f'unfiltered_jobs_{timestamp}.json'
        unfiltered_by_errid = defaultdict(list)  # errid -> [bad_job_id, ...]
        unfiltered_by_reason = defaultdict(list)  # reason -> [{job_info}, ...]

        for job_info in unfiltered_jobs:
            bad_job_id = job_info.get('bad_job_id') or job_info.get('id')
            reason = job_info.get('reason', 'unknown')
            original_errids = job_info.get('errid_list', [])

            # Record grouped by reason (with details)
            unfiltered_by_reason[reason].append({
                'bad_job_id': bad_job_id,
                'git_url': job_info.get('git_url', ''),
                'full_text_kv_sample': job_info.get('full_text_kv_sample', '')[:200]
            })

            # If no errid_list, try to parse from errid string
            if not original_errids and job_info.get('errid'):
                original_errids = smart_split_error_ids(job_info.get('errid', ''))

            repo_info = get_repo_info_from_job_data(bad_job_id, job_data_list)

            # Record each error ID
            for errid in original_errids:
                unfiltered_by_errid[errid].append({
                    'bad_job_id': bad_job_id,
                    'repo_name': repo_info.get('repo_name', 'unknown'),
                    'git_url': repo_info.get('git_url', ''),
                    'commit_sample': repo_info.get('commit_sample', ''),
                    'reason': reason
                })

        # Write grouped by error ID
        unfiltered_grouped_data = {}
        for errid, tasks in unfiltered_by_errid.items():
            # Group by repository
            by_repo = defaultdict(list)
            for task in tasks:
                repo_key = f"{task['repo_name']} @ {task['commit_sample']}" if task['commit_sample'] else task['repo_name']
                by_repo[repo_key].append(task['bad_job_id'])

            unfiltered_grouped_data[errid] = {
                'total_tasks': len(tasks),
                'reason': tasks[0].get('reason', 'no_intelligent_filter_match'),
                'by_repository': dict(by_repo),
                'timestamp': timestamp
            }

        # Merge data grouped by reason
        unfiltered_output = {
            'by_errid': unfiltered_grouped_data,
            'by_reason': {reason: {'count': len(jobs), 'samples': jobs[:20]} for reason, jobs in unfiltered_by_reason.items()}
        }

        with open(unfiltered_file, 'w', encoding='utf-8') as f:
            json.dump(unfiltered_output, f, ensure_ascii=False, indent=2)

        # Count per reason
        reason_stats = {reason: len(jobs) for reason, jobs in unfiltered_by_reason.items()}
        logger.info(f"Unfiltered results file written | path: {unfiltered_file} | by_reason: {reason_stats}")

        # 3. Write human-readable text summary
        summary_file = analysis_dir / f'summary_{timestamp}.txt'
        total_jobs = len(job_data_list)
        filtered_jobs = len(filtered_results)
        unfiltered_jobs_count = len(unfiltered_jobs)

        with open(summary_file, 'w', encoding='utf-8') as f:
            f.write(f"Bisect Task Analysis Summary - {timestamp}\n")
            f.write("=" * 50 + "\n")
            f.write(f"Total processed jobs: {total_jobs}\n")
            f.write(f"Successfully filtered: {filtered_jobs}\n")
            f.write(f"Unfiltered jobs: {unfiltered_jobs_count}\n")
            if total_jobs > 0:
                f.write(f"Filter success rate: {filtered_jobs/total_jobs*100:.1f}%\n")
                f.write(f"Unfiltered rate: {unfiltered_jobs_count/total_jobs*100:.1f}%\n\n")
            else:
                f.write("Filter success rate: N/A\n")
                f.write("Unfiltered rate: N/A\n\n")

            # Statistics by filter reason
            if unfiltered_by_reason:
                f.write("Unfiltered tasks by reason:\n")
                f.write("-" * 30 + "\n")
                for reason, jobs in sorted(unfiltered_by_reason.items(), key=lambda x: len(x[1]), reverse=True):
                    f.write(f"  {reason}: {len(jobs)} tasks\n")
                    # Show first 3 examples
                    for sample in jobs[:3]:
                        f.write(f"    - job_id: {sample.get('bad_job_id')} | git_url: {sample.get('git_url', '')[:50]}...\n")
                    if len(jobs) > 3:
                        f.write(f"    ... and {len(jobs)-3} more\n")
                f.write("\n")

            # Filtered error type statistics
            f.write("Filtered error types (sorted by task count):\n")
            f.write("-" * 30 + "\n")
            sorted_filtered = sorted(filtered_grouped_data.items(),
                                   key=lambda x: x[1]['total_tasks'], reverse=True)
            for i, (errid, info) in enumerate(sorted_filtered, 1):  # Show all
                f.write(f"[{i:2}] {errid[:100]}{'...' if len(errid) > 100 else ''} ({info['total_tasks']} tasks):\n")
                f.write(f"    priority: {info['priority']}, error_type: {info['error_type']}\n")
                f.write(f"    scoring_reasons: {', '.join(info['reasons'])}\n")
                if info.get('file_paths'):
                    f.write(f"    file_paths: {', '.join(info['file_paths'][:3])}\n")
                if info.get('flags'):
                    flag_str = ', '.join([k for k, v in info['flags'].items() if v])
                    if flag_str:
                        f.write(f"    flags: {flag_str}\n")
                f.write("    Grouped by repo and commit:\n")
                for repo, job_ids in info['by_repository'].items():
                    f.write(f"    {repo}: {len(job_ids)} tasks\n")
                    # Show some job_ids as examples
                    sample_ids = job_ids[:3]
                    if len(job_ids) > 3:
                        f.write(f"      {', '.join(sample_ids)} ... (and {len(job_ids)-3} more)\n")
                    else:
                        f.write(f"      {', '.join(job_ids)}\n")
                f.write("\n")

            # Unfiltered error type statistics
            f.write("\nUnfiltered error types (sorted by task count):\n")
            f.write("-" * 30 + "\n")
            sorted_unfiltered = sorted(unfiltered_grouped_data.items(),
                                     key=lambda x: x[1]['total_tasks'], reverse=True)
            for i, (errid, info) in enumerate(sorted_unfiltered, 1):  # Show all
                f.write(f"[{i:2}] {errid[:100]}{'...' if len(errid) > 100 else ''} ({info['total_tasks']} tasks):\n")
                f.write(f"    reason: {info.get('reason', 'unknown')}\n")
                f.write("    Grouped by repo and commit:\n")
                for repo, job_ids in info['by_repository'].items():
                    f.write(f"    {repo}: {len(job_ids)} tasks\n")
                f.write("\n")

            f.write("\nDetailed data files:\n")
            f.write(f"- Filtered results: {filtered_file.name}\n")
            f.write(f"- Unfiltered results: {unfiltered_file.name}\n")

        logger.info(f"Summary file written | path: {summary_file}")

    except Exception as e:
        logger.error(f"Failed to write analysis files: {str(e)}")
        logger.error(f"Exception details: {traceback.format_exc()}")


def extract_repo_name_from_url(git_url: str) -> str:
    """Extract repository name from git_url"""
    if not git_url:
        return 'unknown_repo'

    # Remove .git suffix, get base name
    repo_name = os.path.basename(git_url.rstrip('/'))
    if repo_name.endswith('.git'):
        repo_name = repo_name[:-4]

    # Ensure name safety (remove special characters)
    repo_name = re.sub(r'[^\w\-]', '_', repo_name)
    return repo_name if repo_name else 'unknown_repo'


def categorize_bisect_task(task_data: dict, full_text_kv: str = '') -> str:
    """
    Auto-categorize bisect tasks as build/function/benchmark
    - Has bisect_metric -> benchmark
    - Suite is makepkg/pkgbuild or contains build patterns -> build
    - Otherwise -> function
    """
    # If has bisect_metric, it's a performance test
    if task_data.get('bisect_metric'):
        return 'benchmark'

    # Check build-related patterns
    if full_text_kv:
        import re

        # Check multiple build-related patterns
        build_patterns = [
            r'suite=(?:makepkg|pkgbuild)',  # Original pattern
            r'pp\.makepkg\.',               # pp.makepkg._url etc
            r'testcase=build-pkg',          # build-pkg test case
            r'program\.makepkg\.',          # program.makepkg._url etc
            r'suite=(?:build|compile)',     # build/compile suite
            r'testcase=(?:build|compile)',  # build/compile testcase
        ]

        for pattern in build_patterns:
            if re.search(pattern, full_text_kv, re.IGNORECASE):
                return 'build'

    # Default to function test
    return 'function'


def format_error_ids(error_ids: list) -> str:
    """Format error ID list as readable multi-line string"""
    if not error_ids:
        return "[]"

    # Get configuration values
    sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
    from config import Config

    max_per_line = Config.ERROR_ID_MAX_PER_LINE
    max_length = Config.ERROR_ID_MAX_LENGTH

    # Shorten overly long error IDs
    shortened_ids = []
    for errid in error_ids:
        if len(errid) > max_length:
            prefix = errid[:30]
            suffix = errid[-30:]
            shortened_ids.append(f"{prefix}...{suffix}")
        else:
            shortened_ids.append(errid)

    # Group display
    lines = []
    for i in range(0, len(shortened_ids), max_per_line):
        group = shortened_ids[i:i+max_per_line]
        lines.append(", ".join(f"'{item}'" for item in group))

    return f"[\n  " + "\n  ".join(lines) + "\n]"


def get_parent_commit(repo_dir: str, commit: str) -> Optional[str]:
    """
    Get parent commit of specified commit

    Args:
        repo_dir: repository directory
        commit: commit hash

    Returns:
        Parent commit hash or None
    """
    try:
        result = subprocess.run(
            ['git', '-C', repo_dir, 'rev-parse', f'{commit}^'],
            capture_output=True,
            text=True,
            check=True,
            timeout=60
        )
        parent_commit = result.stdout.strip()
        logger.info(f"Got parent commit | commit: {commit[:8]} -> parent: {parent_commit[:8]}")
        return parent_commit
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to get parent commit | commit: {commit[:8]} | error: {e.stderr}")
        return None
    except subprocess.TimeoutExpired:
        logger.error("Get parent commit timed out")
        return None
    except Exception as e:
        logger.error(f"Get parent commit error: {str(e)}")
        return None


def cleanup_repo_dir(job_dir: str):
    """
    Clean up repository directory

    Args:
        job_dir: job directory
    """
    try:
        if os.path.exists(job_dir):
            shutil.rmtree(job_dir, ignore_errors=True)
            logger.debug(f"Repository directory cleaned up: {job_dir}")
    except Exception as e:
        logger.error(f"Failed to clean up repository directory: {str(e)} | path: {job_dir}")


def generate_task_path(config: dict, task: dict) -> str:
    """
    Generate task path

    Args:
        config: config dictionary
        task: task data

    Returns:
        Task path string
    """
    repo_name = extract_repo_name_from_url(task.get('git_url'))
    result_base = os.environ.get('RESULT_DIR', '/result/bisect')
    path = os.path.join(
        result_base,
        'results',
        repo_name,
        datetime.now().strftime("%Y-%m-%d"),
        str(task['bad_job_id']),
        hashlib.md5(task['error_id'].encode()).hexdigest()[:8],
        str(task['id'])
    )
    os.makedirs(path, exist_ok=True, mode=0o755)
    return os.path.abspath(path)


def validate_task_data(task: dict) -> dict:
    """
    Validate task data

    Args:
        task: task data dictionary

    Returns:
        Validated task data

    Raises:
        ValueError: when task data is invalid
    """
    # Ensure j field is not null
    if 'j' in task and task['j'] is None:
        logger.warning(f"Cleaning invalid j field | TaskID={task.get('id')}")
        task['j'] = {}  # Set to empty dictionary

    # Ensure basic required fields exist
    if 'bad_job_id' not in task:
        raise ValueError("Missing required field: bad_job_id")

    # Check task type field - must have either error_id or bisect_metric
    has_error_id = "error_id" in task and task["error_id"]
    has_metrics = "bisect_metric" in task and task["bisect_metric"]

    if not has_error_id and not has_metrics:
        raise ValueError("Missing task type field: must specify either error_id or bisect_metric")

    if has_error_id and has_metrics:
        raise ValueError("Task type conflict: cannot specify both error_id and bisect_metric")

    return task


def batch_check_existing_tasks(client, job_id: int, task_identifiers: list, task_type: str = "error_id") -> set:
    """
    Batch check which tasks already exist

    Args:
        client: ManticoreClient instance
        job_id: job ID
        task_identifiers: task identifier list
        task_type: task type ("error_id" or "bisect_metric")

    Returns:
        Set of existing task identifiers
    """
    if not task_identifiers:
        return set()

    try:
        # Only consider active tasks as duplicates;
        # failed tasks should not block new bisect attempts
        active_status_filter = {"in": {"bisect_status": ["wait", "processing", "verifying", "success"]}}

        # Build different queries based on task type
        if task_type == "error_id":
            # Build batch query - error ID type
            must_conditions = [
                {"equals": {"bad_job_id": str(job_id)}},
                {"in": {"error_id": task_identifiers}},
                active_status_filter
            ]
            select_field = "error_id"
        else:
            # bisect_metric type
            must_conditions = [
                {"equals": {"bad_job_id": str(job_id)}},
                {"in": {"bisect_metric": task_identifiers}},
                active_status_filter
            ]
            select_field = "bisect_metric"

        # Query using ManticoreSearch
        query = {
            "bool": {
                "must": must_conditions
            }
        }

        result = client.search(index="bisect", query=query, limit=len(task_identifiers))

        existing_ids = {item.get(select_field) for item in result if item.get(select_field)} if result else set()

        logger.debug(f"Job {job_id}: {len(existing_ids)}/{len(task_identifiers)} {task_type}s already exist")
        return existing_ids

    except Exception as e:
        logger.error(f"Batch check failed: {str(e)}")
        return set()


def get_bisect_statistics(client) -> Dict[str, float]:
    """
    Get bisect statistics

    Args:
        client: ManticoreClient instance

    Returns:
        Statistics dictionary
    """
    try:
        # Get bisect stats for last 30 days
        time_threshold = int(time.time()) - 86400 * 30

        # Query total tasks - updated in last 30 days
        total_query = {
            "bool": {
                "must": [
                    {"range": {"updated_at": {"gt": time_threshold}}}
                ]
            }
        }

        total_result = client.search(
            index="bisect",
            query=total_query,
            limit=10000  # Set large enough limit
        )

        total_tasks = len(total_result) if total_result else 0

        # Query successful task count
        success_query = {
            "bool": {
                "must": [
                    {"range": {"updated_at": {"gt": time_threshold}}},
                    {"equals": {"bisect_status": "success"}}
                ]
            }
        }

        success_result = client.search(
            index="bisect",
            query=success_query,
            limit=10000
        )

        success_count = len(success_result) if success_result else 0

        # Count unique error IDs (simplified, using set dedup)
        unique_errors = len(set(item.get('error_id', '') for item in total_result if item.get('error_id'))) if total_result else 0

        success_rate = success_count / total_tasks if total_tasks > 0 else 0

        # Estimate coverage (needs comparison with jobs table)
        # Simplified to estimate based on whitelist size

        return {
            'success_rate': success_rate,
            'total_tasks': total_tasks,
            'success_count': success_count,
            'unique_error_count': unique_errors
        }

    except Exception as e:
        logger.error(f"Failed to get bisect stats: {str(e)}")
        return {'success_rate': 0.0, 'coverage_rate': 0.0, 'total_tasks': 0, 'success_count': 0, 'unique_error_count': 0}


def cleanup_task_workspace(task_id: str, repo_base_dir: str):
    """
    Clean up task workspace

    Args:
        task_id: task ID
        repo_base_dir: repository base directory
    """
    try:
        task_workspace_dir = os.path.join(repo_base_dir, str(task_id))
        if os.path.exists(task_workspace_dir):
            shutil.rmtree(task_workspace_dir, ignore_errors=True)
            logger.info(f"Cleaned task workspace: {task_workspace_dir}")
        else:
            logger.debug(f"Task workspace already clean: {task_workspace_dir}")
    except Exception as e:
        logger.error(f"Failed to clean task workspace {task_id}: {str(e)}")


def wait_for_status(bisect_instance, job_ids: List[str], check_completed: bool = True) -> bool:
    """
    Wait for jobs to reach specified status (generic utility function)

    Args:
        bisect_instance: GitBisect instance, used to call _poll_job_stats
        job_ids: job ID list, elements can be strings or tuples (job_id, result_root)
        check_completed: whether to check job completed (True) or still running (False)

    Returns:
        bool: True if all jobs reached specified status, False otherwise
    """
    try:
        for job_id_entry in job_ids:
            # Handle two formats: string or tuple (job_id, result_root)
            if isinstance(job_id_entry, tuple):
                job_id, result_root = job_id_entry
                job_stats, job_health = bisect_instance._poll_job_stats(job_id, result_root)
            else:
                job_id = job_id_entry
                job_stats, job_health = bisect_instance._poll_job_stats(job_id)

            if check_completed:
                # Check if job completed: job_stats is dict and non-empty means completed
                if isinstance(job_stats, dict) and not job_stats:
                    logger.debug(f"Job still running | job_id: {job_id}")
                    return False
            else:
                # Check if job still running
                if not isinstance(job_stats, dict) or job_stats:
                    logger.debug(f"Job completed or has results | job_id: {job_id}")
                    return False

        return True

    except Exception as e:
        logger.error(f"Error checking job status: {str(e)}")
        return False


def write_regression_record(client, task_data: dict, bad_commit: str) -> bool:
    """
    Write regression record to regression table

    This function should be called after success validation,
    ensuring only verified bisect results are written to regression table.

    Args:
        client: ManticoreClient instance
        task_data: task data dict, must contain error_id, bad_job_id
        bad_commit: first_bad_commit hash

    Returns:
        bool: True on success, False on failure
    """
    try:
        error_id = task_data.get('error_id', '')
        bad_job_id = task_data.get('bad_job_id', '')

        if not error_id or not bad_commit:
            logger.warning(f"Skipping regression write | error_id or bad_commit is empty")
            return False

        # Generate record ID
        record_id = hashlib.sha256(f"errid|{error_id}|{int(time.time())}".encode()).hexdigest()
        record_id_int = int(record_id[:15], 16)  # Convert to bigint

        current_time = int(time.time())

        # Check if record with same error_id already exists
        existing_query = {
            "bool": {
                "must": [
                    {"equals": {"record_type": "errid"}},
                    {"equals": {"errid": error_id}}
                ]
            }
        }

        existing = client.search(index="regression", query=existing_query, limit=1)

        if existing and len(existing) > 0:
            # Update existing record
            existing_record = existing[0]
            existing_id = existing_record.get('id')

            # Read and preserve existing j field
            existing_j = existing_record.get('j', {})
            if isinstance(existing_j, str):
                import json
                existing_j = json.loads(existing_j)
            if not existing_j or not isinstance(existing_j, dict):
                existing_j = {}

            # Basic field update
            update_doc = {
                "last_seen": current_time,
                "submit_time": current_time,
                "status": "active",
                # related_job and related_commit are string fields, store latest values
                "related_job": bad_job_id,
                "related_commit": bad_commit
            }

            # Maintain complete history in j field
            jobs_history = existing_j.get('related_jobs_history', [])
            if not isinstance(jobs_history, list):
                jobs_history = []
            if bad_job_id and bad_job_id not in jobs_history:
                jobs_history.append(bad_job_id)

            commits_history = existing_j.get('related_commits_history', [])
            if not isinstance(commits_history, list):
                commits_history = []
            if bad_commit and bad_commit not in commits_history:
                commits_history.append(bad_commit)

            # Update j field (preserve HEAD check data, add history)
            updated_j = {
                **existing_j,  # Preserve existing data (e.g. HEAD check)
                "related_jobs_history": jobs_history,
                "related_commits_history": commits_history
            }

            update_doc["j"] = updated_j

            success = client.update("regression", existing_id, update_doc)
            if success:
                logger.info(f"Updated regression record | error_id: {error_id} | job: {bad_job_id}")
            else:
                logger.error(f"Failed to update regression record | error_id: {error_id}")
            return success

        else:
            # Create new record
            regression_doc = {
                "id": record_id_int,
                "record_type": "errid",
                "errid": error_id,
                "first_seen": current_time,
                "last_seen": current_time,
                "submit_time": current_time,
                "metric_name": "",
                "direction": "",
                "status": "active",
                # related_job and related_commit are strings, store latest values
                "related_job": bad_job_id,
                "related_commit": bad_commit if bad_commit else "",
                # Initialize j field with history
                "j": {
                    "related_jobs_history": [bad_job_id] if bad_job_id else [],
                    "related_commits_history": [bad_commit] if bad_commit else []
                }
            }

            success = client.insert("regression", record_id_int, regression_doc)
            if success:
                logger.info(f"Created regression record | error_id: {error_id} | record_id: {record_id_int}")
            else:
                logger.error(f"Failed to create regression record | error_id: {error_id}")
            return success

    except Exception as e:
        logger.error(f"Regression write error | error_id: {task_data.get('error_id')} | error: {str(e)}")
        logger.error(traceback.format_exc())
        return False


def mark_similar_wait_tasks_for_verification(client, errid_intelligence, successful_task: Dict):
    """
    On task success, batch mark wait tasks with same signature as verifying

    Important: only match tasks in same git repo, avoid cross-repo false matches

    Args:
        client: ManticoreClient instance
        errid_intelligence: ErridIntelligence instance
        successful_task: successful task info (contains id, error_id, category, git_url fields)
    """
    try:
        task_id = successful_task.get('id')
        error_id = successful_task.get('error_id', '')
        category = successful_task.get('category', 'function')
        success_git_url = successful_task.get('git_url', '')

        # Only process build tasks (other types do not use signature clustering)
        if category != 'build' or not error_id:
            logger.debug(f"Task {task_id} does not need similar task processing | category: {category} | has_error_id: {bool(error_id)}")
            return

        # Must have git_url to match
        if not success_git_url:
            logger.warning(f"Task {task_id} missing git_url, cannot match similar tasks")
            return

        # Extract error signature
        signature = errid_intelligence.extract_coarse_signature(error_id)

        # Only reuse when signature has a real file path (e.g., "nbl_core/nbl_service.c::error")
        # Config-stage signatures without file paths (makepkg::, stderr::, unknown_file::)
        # are too coarse and cause false matches
        file_key = signature.split('::')[0]
        if '/' not in file_key and '.' not in file_key:
            logger.info(f"Task {task_id} has no-file signature '{signature}', skipping coarse reuse")
            return

        logger.info(f"Task {task_id} succeeded, searching for wait tasks with same signature | signature: {signature} | git_url: {success_git_url[:60]}...")

        # Query all wait tasks with same signature
        # Strategy: query build tasks in wait status, filter by signature on client side
        query = f"""
            SELECT id, error_id, bad_job_id, git_url, submit_time, priority_level
            FROM bisect
            WHERE bisect_status = 'wait' AND category = 'build'
            LIMIT {Config.WAIT_TASK_QUERY_LIMIT}
        """

        wait_tasks = client.sql_select(query)

        if not wait_tasks:
            logger.info(f"No build tasks found in wait status")
            return

        # Client-side filter: find tasks with same signature and same repo
        similar_tasks = []
        skipped_cross_repo = 0

        for wait_task in wait_tasks:
            wait_error_id = wait_task.get('error_id', '')
            wait_git_url = wait_task.get('git_url', '')

            if not wait_error_id:
                continue

            try:
                wait_signature = errid_intelligence.extract_coarse_signature(wait_error_id)

                # Key fix: must match both signature and git_url
                if wait_signature == signature:
                    if wait_git_url == success_git_url:
                        similar_tasks.append(wait_task)
                    else:
                        skipped_cross_repo += 1
                        logger.debug(
                            f"Skipping cross-repo task | wait_task: {wait_task.get('id')} | "
                            f"wait_repo: {wait_git_url[:50]}... | "
                            f"success_repo: {success_git_url[:50]}..."
                        )
            except Exception as e:
                logger.warning(f"Failed to extract signature | task_id: {wait_task.get('id')} | error: {str(e)}")
                continue

        if not similar_tasks:
            if skipped_cross_repo > 0:
                logger.warning(
                    f"No same-repo similar tasks found | signature: {signature} | "
                    f"skipped {skipped_cross_repo} cross-repo tasks"
                )
            else:
                logger.info(f"No wait tasks found with same signature | signature: {signature}")
            return

        logger.info(
            f"Found {len(similar_tasks)} same-repo similar tasks, starting batch mark as verifying | "
            f"cross_repo_skipped: {skipped_cross_repo}"
        )

        # Batch mark as verifying
        current_time = int(time.time())
        success_count = 0
        failed_count = 0

        for similar_task in similar_tasks:
            try:
                similar_task_id = similar_task['id']

                doc = {
                    "bisect_status": "verifying",
                    "updated_at": current_time,
                    "j": {
                        "related_task_id": str(task_id),
                        "error_signature": signature,
                        "original_error_id": similar_task.get('error_id', ''),
                        "auto_marked_by_success": True,
                        "auto_marked_timestamp": current_time
                    }
                }

                update_result = client.update("bisect", similar_task_id, doc)

                if update_result:
                    success_count += 1
                    logger.debug(f"Task {similar_task_id} marked as verifying, linked to successful task {task_id}")
                else:
                    failed_count += 1
                    logger.warning(f"Task {similar_task_id} marking failed")

            except Exception as e:
                failed_count += 1
                logger.error(f"Failed to mark task {similar_task.get('id', 'unknown')}: {str(e)}")

        logger.info(f"Batch marking completed | success: {success_count} | failed: {failed_count} | linked_task: {task_id}")

    except Exception as e:
        logger.error(f"Failed to process similar tasks: {str(e)}")
        logger.error(traceback.format_exc())


def mark_introduced_errid_tasks_for_verification(client, successful_task: Dict):
    """
    On task success, batch mark wait tasks matching introduced_errids as verifying

    Important: only match tasks in same git repo, avoid cross-repo false matches

    Only process build tasks (only build tasks have introduced_errids)

    Args:
        client: ManticoreClient instance
        successful_task: successful task info (contains id, category, git_url, j.introduced_errids fields)
    """
    try:
        task_id = successful_task.get('id')
        category = successful_task.get('category', 'function')
        success_git_url = successful_task.get('git_url', '')

        # Only process build tasks
        if category != 'build':
            logger.debug(f"Task {task_id} is not a build task, skipping introduced_errids processing | category: {category}")
            return

        # Must have git_url to match
        if not success_git_url:
            logger.warning(f"Task {task_id} missing git_url, cannot match introduced_errids tasks")
            return

        # Read introduced_errids from j field
        j_field = successful_task.get('j') or {}
        if isinstance(j_field, str):
            try:
                j_field = json.loads(j_field) if j_field else {}
            except json.JSONDecodeError:
                j_field = {}

        introduced_errids = j_field.get('introduced_errids', [])

        if not introduced_errids:
            logger.debug(f"Task {task_id} has no introduced_errids, skipping")
            return

        if not isinstance(introduced_errids, list):
            logger.warning(f"Task {task_id} introduced_errids is not a list: {type(introduced_errids)}")
            return

        logger.info(
            f"Task {task_id} succeeded, searching for wait tasks matching introduced_errids | "
            f"errids: {len(introduced_errids)} | git_url: {success_git_url[:60]}..."
        )

        # Query all build tasks in wait status
        query = f"""
            SELECT id, error_id, bad_job_id, git_url, submit_time, priority_level
            FROM bisect
            WHERE bisect_status = 'wait' AND category = 'build'
            LIMIT {Config.WAIT_TASK_QUERY_LIMIT}
        """

        wait_tasks = client.sql_select(query)

        if not wait_tasks:
            logger.info(f"No build tasks found in wait status")
            return

        # Client-side filter: find tasks with error_id in introduced_errids list and same repo
        matched_tasks = []
        skipped_cross_repo = 0

        for wait_task in wait_tasks:
            wait_error_id = wait_task.get('error_id', '')
            wait_git_url = wait_task.get('git_url', '')

            if not wait_error_id:
                continue

            if wait_error_id in introduced_errids:
                # Key fix: must be same repo
                if wait_git_url == success_git_url:
                    matched_tasks.append(wait_task)
                else:
                    skipped_cross_repo += 1
                    logger.debug(
                        f"Skipping cross-repo task | wait_task: {wait_task.get('id')} | "
                        f"error_id: {wait_error_id[:60]}... | "
                        f"wait_repo: {wait_git_url[:50]}... | "
                        f"success_repo: {success_git_url[:50]}..."
                    )

        if not matched_tasks:
            if skipped_cross_repo > 0:
                logger.warning(
                    f"No same-repo matching tasks found | errids: {len(introduced_errids)} | "
                    f"skipped {skipped_cross_repo} cross-repo tasks"
                )
            else:
                logger.info(f"No wait tasks found matching introduced_errids | errids: {len(introduced_errids)}")
            return

        logger.info(
            f"Found {len(matched_tasks)} same-repo matching tasks, starting batch mark as verifying | "
            f"cross_repo_skipped: {skipped_cross_repo}"
        )

        # Batch mark as verifying
        current_time = int(time.time())
        success_count = 0
        failed_count = 0

        for matched_task in matched_tasks:
            try:
                matched_task_id = matched_task['id']

                doc = {
                    "bisect_status": "verifying",
                    "updated_at": current_time,
                    "j": {
                        "related_task_id": str(task_id),
                        "original_error_id": matched_task.get('error_id', ''),
                        "auto_marked_by_introduced_errids": True,
                        "auto_marked_timestamp": current_time
                    }
                }

                update_result = client.update("bisect", matched_task_id, doc)

                if update_result:
                    success_count += 1
                    logger.debug(f"Task {matched_task_id} marked as verifying, linked to successful task {task_id}")
                else:
                    failed_count += 1
                    logger.warning(f"Task {matched_task_id} marking failed")

            except Exception as e:
                failed_count += 1
                logger.error(f"Failed to mark task {matched_task.get('id', 'unknown')}: {str(e)}")

        logger.info(f"Batch marking completed (introduced_errids) | success: {success_count} | failed: {failed_count} | linked_task: {task_id}")

    except Exception as e:
        logger.error(f"Failed to process introduced_errids tasks: {str(e)}")
        logger.error(traceback.format_exc())