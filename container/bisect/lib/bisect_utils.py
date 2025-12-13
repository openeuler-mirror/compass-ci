#!/usr/bin/env python3
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2024 Huawei Technologies Co., Ltd. All rights reserved.
"""
Bisect 共享工具函数模块
提取 task_processor.py 和 bisect_producer.py 中的重复代码
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

# 导入日志系统
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lib'))
from log_config import logger

def _generate_task_id(bad_job_id, task_identifier):
    """Generate deterministic ID based on task_identifier

    For error_id tasks: ID based only on error_id (same error_id = same task)
    For bisect_metric tasks: ID based on (bad_job_id, bisect_metric)

    task_identifier format: "error_id='xxx'" or "bisect_metric='xxx'"

    Returns:
        19位正整数 ID (1000000000000000000 ~ 9223372036854775807)
    """
    if task_identifier.startswith("error_id="):
        # error_id 任务：只用 error_id 生成 ID，确保相同 error_id 只有一个任务
        unique_str = task_identifier
    else:
        # bisect_metric 任务：用 (bad_job_id, bisect_metric) 生成 ID
        unique_str = f"{bad_job_id}|{task_identifier}"

    hash_bytes = hashlib.sha256(unique_str.encode()).digest()
    hash_int = int.from_bytes(hash_bytes[:8], byteorder='big')

    # 确保 ID 为 19 位数字：
    # - 最小值: 1000000000000000000 (10^18)
    # - 最大值: 9223372036854775807 (2^63 - 1, signed int64 max)
    # 使用模运算将 hash 映射到这个范围
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
        # 将 good_commit 保存到 j 字段中（因为表结构没有 good_commit 字段）
        if validated_data.get("good_commit"):
            task_doc["j"] = {"good_commit": validated_data["good_commit"]}
    else:
        task_doc = {
            "bad_job_id": validated_data["bad_job_id"],
            "bisect_metric": validated_data["bisect_metric"],
            "bisect_status": "wait",
            "submit_time": int(time.time())
        }
        # 将 good_commit 保存到 j 字段中（因为表结构没有 good_commit 字段）
        if validated_data.get("good_commit"):
            task_doc["j"] = {"good_commit": validated_data["good_commit"]}

    return task_doc

def smart_split_error_ids(errid_string: str) -> List[str]:
    """
    智能分割error_id字符串，保持引号内容完整
    处理类似这样的字符串：
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
        logger.debug(f"智能分割结果: {len(result)}个部分")
        for idx, part in enumerate(result[:3]):  # Only show first 3
            logger.debug(f"  {idx+1}: {part[:100]}...")

    return result


def extract_git_url_from_full_text_kv(full_text_kv: str) -> str:
    """从 full_text_kv 中提取完整的 Git 仓库 URL"""
    if not full_text_kv:
        logger.warning("full_text_kv 为空")
        return None

    try:
        logger.debug(f"尝试从 full_text_kv 提取 git_url | 长度: {len(full_text_kv)} | 内容前100字符: {full_text_kv[:100]}...")

        # Find ss.linux._url= or pp.makepkg._url= patterns
        url_pattern = r'(?:ss\.linux\._url|pp\.makepkg\._url)=([^\s]+)'
        url_match = re.search(url_pattern, full_text_kv)

        if url_match:
            url = url_match.group(1)
            logger.debug(f"成功匹配到 git_url | 原始URL: {url}")

            # Standardize URL format
            original_url = url
            if url.startswith("git+http"):
                url = url.replace("git+", "", 1)

            if url != original_url:
                logger.debug(f"URL标准化 | 原始: {original_url} | 标准化: {url}")

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

            logger.debug(f"未找到匹配的git_url模式 | full_text_kv样例: {full_text_kv[:200]}...")
            return None

    except Exception as e:
        logger.error(f"提取git_url时出错: {e}")
        logger.debug(f"异常详情: {traceback.format_exc()}")
        return None


def extract_commit_from_full_text_kv(full_text_kv: str) -> str:
    """从 full_text_kv 中提取 commit hash 或 tag

    Args:
        full_text_kv: jobs 表的 full_text_kv 字段

    Returns:
        Commit hash 或 tag，未找到返回空字符串

    支持的格式：
        - commit: abc123... (40位完整hash)
        - commit: abc123 (12+位短hash)
        - commit: v6.17 (tag格式)
        - head/HEAD: ...
    """
    if not full_text_kv:
        return ''

    try:
        # 优先匹配 commit hash（更精确）
        hash_patterns = [
            r'commit[:=]\s*([a-f0-9]{40})',          # commit: abc123... (完整40位)
            r'commit[:=]\s*([a-f0-9]{12,})',         # commit: abc123 (12+位)
            r'head[:=]\s*([a-f0-9]{40})',            # head: abc123...
            r'HEAD[:=]\s*([a-f0-9]{40})',            # HEAD: abc123...
        ]

        for pattern in hash_patterns:
            match = re.search(pattern, full_text_kv, re.IGNORECASE)
            if match:
                commit_hash = match.group(1)
                logger.debug(f"成功提取 commit hash | hash: {commit_hash[:12]}...")
                return commit_hash

        # 匹配 tag 格式（v开头的版本号，如 v6.17, v5.10-rc1）
        tag_patterns = [
            r'commit[:=]\s*(v\d+\.\d+(?:\.\d+)?(?:-rc\d+)?(?:-\w+)?)\b',  # v6.17, v5.10-rc1, v6.12-openeuler
            r'commit[:=]\s*(v\d+\.\d+[^\s,]*)',                            # v6.17-xxx 更宽松匹配
        ]

        for pattern in tag_patterns:
            match = re.search(pattern, full_text_kv, re.IGNORECASE)
            if match:
                tag = match.group(1)
                logger.debug(f"成功提取 commit tag | tag: {tag}")
                return tag

        logger.debug("未找到 commit hash 或 tag")
        return ''

    except Exception as e:
        logger.error(f"提取 commit 时出错: {e}")
        return ''


def get_repo_info_from_job_data(bad_job_id: str, job_data_list: List[Dict]) -> Dict[str, str]:
    """从job_data_list中获取仓库信息"""
    try:
        # 查找对应的job数据
        job_data = None
        for item in job_data_list:
            if str(item.get('id')) == str(bad_job_id):
                job_data = item
                break

        if not job_data:
            return {'repo_name': 'unknown', 'git_url': '', 'commit_sample': ''}

        # 提取git_url
        git_url = extract_git_url_from_full_text_kv(job_data.get('full_text_kv', ''))

        # 使用本模块中的 extract_repo_name_from_url 函数
        repo_name = extract_repo_name_from_url(git_url) if git_url else 'unknown'

        # 尝试提取commit信息（简化版本，取前8位）
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
        logger.debug(f"获取仓库信息失败: {str(e)}")
        return {'repo_name': 'unknown', 'git_url': '', 'commit_sample': ''}


def write_analysis_files(job_data_list: List[Dict],
                         filtered_results: Dict,
                         unfiltered_jobs: List[Dict]) -> None:
    """将分析结果写入文件供人工确认，按错误ID归类显示"""
    try:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        # 创建分析文件目录
        analysis_dir = Path(os.environ.get('RESULT_DIR', '/result/bisect')) / 'logs' / 'analysis'
        analysis_dir.mkdir(exist_ok=True, parents=True)

        # 1. 记录被筛选的任务（成功筛选出的），按错误ID归类
        filtered_file = analysis_dir / f'filtered_jobs_{timestamp}.json'
        filtered_by_errid = defaultdict(list)  # errid -> [task_info, ...]

        for bad_job_id, selected_errids in filtered_results.items():
            # 获取仓库信息
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

        # 按错误ID分组写入
        filtered_grouped_data = {}
        for errid, tasks in filtered_by_errid.items():
            # 按仓库分组
            by_repo = defaultdict(list)
            for task in tasks:
                repo_key = f"{task['repo_name']} @ {task['commit_sample']}" if task['commit_sample'] else task['repo_name']
                by_repo[repo_key].append(task['bad_job_id'])

            filtered_grouped_data[errid] = {
                'total_tasks': len(tasks),
                'priority': tasks[0]['priority'],  # 同一个errid优先级相同
                'error_type': tasks[0]['error_type'],
                'reasons': tasks[0]['reasons'],
                'file_paths': tasks[0]['file_paths'],
                'flags': tasks[0]['flags'],
                'by_repository': dict(by_repo),
                'timestamp': timestamp
            }

        with open(filtered_file, 'w', encoding='utf-8') as f:
            json.dump(filtered_grouped_data, f, ensure_ascii=False, indent=2)

        logger.info(f"已写入筛选结果文件 | 路径: {filtered_file} | 错误ID种类: {len(filtered_grouped_data)}")

        # 2. 记录未被智能过滤的任务，按原因和错误ID归类
        unfiltered_file = analysis_dir / f'unfiltered_jobs_{timestamp}.json'
        unfiltered_by_errid = defaultdict(list)  # errid -> [bad_job_id, ...]
        unfiltered_by_reason = defaultdict(list)  # reason -> [{job_info}, ...]

        for job_info in unfiltered_jobs:
            bad_job_id = job_info.get('bad_job_id') or job_info.get('id')
            reason = job_info.get('reason', 'unknown')
            original_errids = job_info.get('errid_list', [])

            # 按原因分组记录（包含详细信息）
            unfiltered_by_reason[reason].append({
                'bad_job_id': bad_job_id,
                'git_url': job_info.get('git_url', ''),
                'full_text_kv_sample': job_info.get('full_text_kv_sample', '')[:200]
            })

            # 如果没有 errid_list，尝试从 errid 字符串解析
            if not original_errids and job_info.get('errid'):
                original_errids = smart_split_error_ids(job_info.get('errid', ''))

            repo_info = get_repo_info_from_job_data(bad_job_id, job_data_list)

            # 将每个错误ID都记录
            for errid in original_errids:
                unfiltered_by_errid[errid].append({
                    'bad_job_id': bad_job_id,
                    'repo_name': repo_info.get('repo_name', 'unknown'),
                    'git_url': repo_info.get('git_url', ''),
                    'commit_sample': repo_info.get('commit_sample', ''),
                    'reason': reason
                })

        # 按错误ID分组写入
        unfiltered_grouped_data = {}
        for errid, tasks in unfiltered_by_errid.items():
            # 按仓库分组
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

        # 合并按原因分组的数据
        unfiltered_output = {
            'by_errid': unfiltered_grouped_data,
            'by_reason': {reason: {'count': len(jobs), 'samples': jobs[:20]} for reason, jobs in unfiltered_by_reason.items()}
        }

        with open(unfiltered_file, 'w', encoding='utf-8') as f:
            json.dump(unfiltered_output, f, ensure_ascii=False, indent=2)

        # 统计各原因的数量
        reason_stats = {reason: len(jobs) for reason, jobs in unfiltered_by_reason.items()}
        logger.info(f"已写入未筛选结果文件 | 路径: {unfiltered_file} | 按原因: {reason_stats}")

        # 3. 写入可读性更强的文本汇总
        summary_file = analysis_dir / f'summary_{timestamp}.txt'
        total_jobs = len(job_data_list)
        filtered_jobs = len(filtered_results)
        unfiltered_jobs_count = len(unfiltered_jobs)

        with open(summary_file, 'w', encoding='utf-8') as f:
            f.write(f"Bisect任务分析汇总 - {timestamp}\n")
            f.write("=" * 50 + "\n")
            f.write(f"总处理任务数: {total_jobs}\n")
            f.write(f"成功筛选任务数: {filtered_jobs}\n")
            f.write(f"未筛选任务数: {unfiltered_jobs_count}\n")
            if total_jobs > 0:
                f.write(f"筛选成功率: {filtered_jobs/total_jobs*100:.1f}%\n")
                f.write(f"未筛选率: {unfiltered_jobs_count/total_jobs*100:.1f}%\n\n")
            else:
                f.write("筛选成功率: N/A\n")
                f.write("未筛选率: N/A\n\n")

            # 按过滤原因分类统计
            if unfiltered_by_reason:
                f.write("未筛选任务按原因分类:\n")
                f.write("-" * 30 + "\n")
                for reason, jobs in sorted(unfiltered_by_reason.items(), key=lambda x: len(x[1]), reverse=True):
                    f.write(f"  {reason}: {len(jobs)} 个任务\n")
                    # 显示前3个样例
                    for sample in jobs[:3]:
                        f.write(f"    - job_id: {sample.get('bad_job_id')} | git_url: {sample.get('git_url', '')[:50]}...\n")
                    if len(jobs) > 3:
                        f.write(f"    ... 还有 {len(jobs)-3} 个\n")
                f.write("\n")

            # 筛选成功的错误分类统计
            f.write("筛选成功的错误类型 (按任务数量排序):\n")
            f.write("-" * 30 + "\n")
            sorted_filtered = sorted(filtered_grouped_data.items(),
                                   key=lambda x: x[1]['total_tasks'], reverse=True)
            for i, (errid, info) in enumerate(sorted_filtered, 1):  # 显示所有
                f.write(f"[{i:2}] {errid[:100]}{'...' if len(errid) > 100 else ''} ({info['total_tasks']} 个任务):\n")
                f.write(f"    优先级: {info['priority']}, 错误类型: {info['error_type']}\n")
                f.write(f"    评分原因: {', '.join(info['reasons'])}\n")
                if info.get('file_paths'):
                    f.write(f"    文件路径: {', '.join(info['file_paths'][:3])}\n")
                if info.get('flags'):
                    flag_str = ', '.join([k for k, v in info['flags'].items() if v])
                    if flag_str:
                        f.write(f"    标志: {flag_str}\n")
                f.write("    按仓库和提交分组:\n")
                for repo, job_ids in info['by_repository'].items():
                    f.write(f"    {repo}: {len(job_ids)}个任务\n")
                    # 显示部分job_id作为样例
                    sample_ids = job_ids[:3]
                    if len(job_ids) > 3:
                        f.write(f"      {', '.join(sample_ids)} ... (还有{len(job_ids)-3}个)\n")
                    else:
                        f.write(f"      {', '.join(job_ids)}\n")
                f.write("\n")

            # 未筛选的错误分类统计
            f.write("\n未筛选的错误类型 (按任务数量排序):\n")
            f.write("-" * 30 + "\n")
            sorted_unfiltered = sorted(unfiltered_grouped_data.items(),
                                     key=lambda x: x[1]['total_tasks'], reverse=True)
            for i, (errid, info) in enumerate(sorted_unfiltered, 1):  # 显示所有
                f.write(f"[{i:2}] {errid[:100]}{'...' if len(errid) > 100 else ''} ({info['total_tasks']} 个任务):\n")
                f.write(f"    原因: {info.get('reason', 'unknown')}\n")
                f.write("    按仓库和提交分组:\n")
                for repo, job_ids in info['by_repository'].items():
                    f.write(f"    {repo}: {len(job_ids)}个任务\n")
                f.write("\n")

            f.write("\n详细数据文件:\n")
            f.write(f"- 筛选结果: {filtered_file.name}\n")
            f.write(f"- 未筛选结果: {unfiltered_file.name}\n")

        logger.info(f"已写入汇总文件 | 路径: {summary_file}")

    except Exception as e:
        logger.error(f"写入分析文件失败: {str(e)}")
        logger.error(f"异常详情: {traceback.format_exc()}")


def extract_repo_name_from_url(git_url: str) -> str:
    """从git_url提取仓库名（从task_processor.py中移动）"""
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
    根据任务特征自动分类bisect任务为 build/function/benchmark
    - 有 bisect_metric → benchmark
    - suite 为 makepkg/pkgbuild 或包含构建相关模式 → build
    - 其余 → function
    （从task_processor.py中移动）
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
    """格式化错误ID列表为易读的多行字符串（从task_processor.py中移动）"""
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
    获取指定提交的父提交（从verification_consumer.py中移动）

    Args:
        repo_dir: 仓库目录
        commit: 提交哈希

    Returns:
        父提交哈希或None
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
        logger.info(f"获取父提交成功 | commit: {commit[:8]} -> parent: {parent_commit[:8]}")
        return parent_commit
    except subprocess.CalledProcessError as e:
        logger.error(f"获取父提交失败 | commit: {commit[:8]} | error: {e.stderr}")
        return None
    except subprocess.TimeoutExpired:
        logger.error("获取父提交超时")
        return None
    except Exception as e:
        logger.error(f"获取父提交异常: {str(e)}")
        return None


def cleanup_repo_dir(job_dir: str):
    """
    清理仓库目录（从verification_consumer.py和head_validator.py中统一）

    Args:
        job_dir: 作业目录
    """
    try:
        if os.path.exists(job_dir):
            shutil.rmtree(job_dir, ignore_errors=True)
            logger.debug(f"仓库目录清理完成: {job_dir}")
    except Exception as e:
        logger.error(f"清理仓库目录失败: {str(e)} | path: {job_dir}")


def generate_task_path(config: dict, task: dict) -> str:
    """
    生成任务路径（从 task_processor.py 迁移）

    Args:
        config: 配置字典
        task: 任务数据

    Returns:
        任务路径字符串
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
    验证任务数据（从 task_processor.py 迁移）

    Args:
        task: 任务数据字典

    Returns:
        验证后的任务数据

    Raises:
        ValueError: 当任务数据无效时
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
    批量检查哪些任务已经存在（从 task_processor.py 迁移）

    Args:
        client: ManticoreClient 实例
        job_id: 作业ID
        task_identifiers: 任务标识符列表
        task_type: 任务类型（"error_id" 或 "bisect_metric"）

    Returns:
        已存在的任务标识符集合
    """
    if not task_identifiers:
        return set()

    try:
        # 根据任务类型构造不同的查询
        if task_type == "error_id":
            # 构造批量查询 - 错误ID类型
            must_conditions = [
                {"equals": {"bad_job_id": str(job_id)}},
                {"in": {"error_id": task_identifiers}}
            ]
            select_field = "error_id"
        else:
            # bisect_metric类型
            must_conditions = [
                {"equals": {"bad_job_id": str(job_id)}},
                {"in": {"bisect_metric": task_identifiers}}
            ]
            select_field = "bisect_metric"

        # 使用ManticoreSearch查询
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
        logger.error(f"批量检查失败: {str(e)}")
        return set()


def get_bisect_statistics(client) -> Dict[str, float]:
    """
    获取bisect统计信息（从 task_processor.py 迁移）

    Args:
        client: ManticoreClient 实例

    Returns:
        统计信息字典
    """
    try:
        # 获取最近30天的bisect统计
        time_threshold = int(time.time()) - 86400 * 30

        # 查询总任务数 - 最近30天更新的任务
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
            limit=10000  # 设置足够大的限制
        )

        total_tasks = len(total_result) if total_result else 0

        # 查询成功任务数
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

        # 计算唯一错误ID数量（简化版本，使用集合去重）
        unique_errors = len(set(item.get('error_id', '') for item in total_result if item.get('error_id'))) if total_result else 0

        success_rate = success_count / total_tasks if total_tasks > 0 else 0

        # 估算覆盖率（需要和jobs表对比）
        # 这里简化为基于白名单大小的估算

        return {
            'success_rate': success_rate,
            'total_tasks': total_tasks,
            'success_count': success_count,
            'unique_error_count': unique_errors
        }

    except Exception as e:
        logger.error(f"获取bisect统计信息失败: {str(e)}")
        return {'success_rate': 0.0, 'coverage_rate': 0.0, 'total_tasks': 0, 'success_count': 0, 'unique_error_count': 0}


def cleanup_task_workspace(task_id: str, repo_base_dir: str):
    """
    清理任务工作目录（从 task_processor.py 迁移）

    Args:
        task_id: 任务ID
        repo_base_dir: 仓库基础目录
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
    等待作业达到指定状态（通用工具函数）

    Args:
        bisect_instance: GitBisect 实例，用于调用 _poll_job_stats
        job_ids: 作业ID列表，元素可以是字符串或元组(job_id, result_root)
        check_completed: 是否检查作业已完成（True）还是仍在运行（False）

    Returns:
        bool: 所有作业都达到指定状态返回 True，否则返回 False
    """
    try:
        for job_id_entry in job_ids:
            # 处理两种格式：字符串或元组(job_id, result_root)
            if isinstance(job_id_entry, tuple):
                job_id, result_root = job_id_entry
                job_stats, job_health = bisect_instance._poll_job_stats(job_id, result_root)
            else:
                job_id = job_id_entry
                job_stats, job_health = bisect_instance._poll_job_stats(job_id)

            if check_completed:
                # 检查作业是否已完成：job_stats 是字典且非空表示完成
                if isinstance(job_stats, dict) and not job_stats:
                    logger.debug(f"作业仍在运行 | job_id: {job_id}")
                    return False
            else:
                # 检查作业是否仍在运行
                if not isinstance(job_stats, dict) or job_stats:
                    logger.debug(f"作业已完成或有结果 | job_id: {job_id}")
                    return False

        return True

    except Exception as e:
        logger.error(f"检查作业状态异常: {str(e)}")
        return False


def write_regression_record(client, task_data: dict, bad_commit: str) -> bool:
    """
    写入回归记录到regression表

    这个函数应该在 success validation 完成后调用，
    确保只有验证通过的 bisect 结果才会写入 regression 表。

    Args:
        client: ManticoreClient 实例
        task_data: 任务数据字典，必须包含 error_id, bad_job_id
        bad_commit: first_bad_commit 哈希值

    Returns:
        bool: 写入成功返回 True，失败返回 False
    """
    try:
        error_id = task_data.get('error_id', '')
        bad_job_id = task_data.get('bad_job_id', '')

        if not error_id or not bad_commit:
            logger.warning(f"跳过regression写入 | error_id或bad_commit为空")
            return False

        # 生成记录ID
        record_id = hashlib.sha256(f"errid|{error_id}|{int(time.time())}".encode()).hexdigest()
        record_id_int = int(record_id[:15], 16)  # 转换为bigint

        current_time = int(time.time())

        # 检查是否已存在相同error_id的记录
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
            # 更新现有记录
            existing_record = existing[0]
            existing_id = existing_record.get('id')

            # 读取并保留现有的 j 字段
            existing_j = existing_record.get('j', {})
            if isinstance(existing_j, str):
                import json
                existing_j = json.loads(existing_j)
            if not existing_j or not isinstance(existing_j, dict):
                existing_j = {}

            # 基本字段更新
            update_doc = {
                "last_seen": current_time,
                "submit_time": current_time,
                "status": "active",  # 使用 status 字段（不是 valid）
                # related_job 和 related_commit 是字符串字段，存储最新值
                "related_job": bad_job_id,      # 最新的 job_id
                "related_commit": bad_commit    # 最新的 commit
            }

            # 在 j 字段中维护完整历史
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

            # 更新 j 字段（保留 HEAD 检查数据，添加历史）
            updated_j = {
                **existing_j,  # 保留现有数据（如 HEAD 检查）
                "related_jobs_history": jobs_history,
                "related_commits_history": commits_history
            }

            update_doc["j"] = updated_j

            success = client.update("regression", existing_id, update_doc)
            if success:
                logger.info(f"更新regression记录 | error_id: {error_id} | job: {bad_job_id}")
            else:
                logger.error(f"更新regression记录失败 | error_id: {error_id}")
            return success

        else:
            # 创建新记录
            regression_doc = {
                "id": record_id_int,
                "record_type": "errid",
                "errid": error_id,
                "first_seen": current_time,
                "last_seen": current_time,
                "submit_time": current_time,
                "metric_name": "",
                "direction": "",
                "status": "active",  # 使用 status 字段
                # related_job 和 related_commit 是字符串，存储最新值
                "related_job": bad_job_id,
                "related_commit": bad_commit if bad_commit else "",
                # 初始化 j 字段，包含历史记录
                "j": {
                    "related_jobs_history": [bad_job_id] if bad_job_id else [],
                    "related_commits_history": [bad_commit] if bad_commit else []
                }
            }

            success = client.insert("regression", record_id_int, regression_doc)
            if success:
                logger.info(f"创建regression记录 | error_id: {error_id} | record_id: {record_id_int}")
            else:
                logger.error(f"创建regression记录失败 | error_id: {error_id}")
            return success

    except Exception as e:
        logger.error(f"regression写入异常 | error_id: {task_data.get('error_id')} | 错误: {str(e)}")
        logger.error(traceback.format_exc())
        return False


def mark_similar_wait_tasks_for_verification(client, errid_intelligence, successful_task: Dict):
    """
    当任务成功时，批量标记相同签名的 wait 任务为 verifying

    Args:
        client: ManticoreClient 实例
        errid_intelligence: ErridIntelligence 实例
        successful_task: 已成功的任务信息（包含 id, error_id, category 等字段）
    """
    try:
        task_id = successful_task.get('id')
        error_id = successful_task.get('error_id', '')
        category = successful_task.get('category', 'function')

        # 只处理构建任务（其他类型不使用签名聚类）
        if category != 'build' or not error_id:
            logger.debug(f"任务 {task_id} 不需要处理相似任务 | category: {category} | has_error_id: {bool(error_id)}")
            return

        # 提取错误签名
        signature = errid_intelligence.extract_coarse_signature(error_id)
        logger.info(f"任务 {task_id} 成功，开始查找相同签名的 wait 任务 | signature: {signature}")

        # 查询所有相同签名的 wait 任务
        # 策略：查询 wait 状态的构建任务，在客户端过滤签名
        query = """
            SELECT id, error_id, bad_job_id, git_url, submit_time, priority_level
            FROM bisect
            WHERE bisect_status = 'wait' AND category = 'build'
            LIMIT 1000
        """

        wait_tasks = client.sql_select(query)

        if not wait_tasks:
            logger.info(f"没有找到 wait 状态的构建任务")
            return

        # 客户端过滤：找到相同签名的任务
        similar_tasks = []
        for wait_task in wait_tasks:
            wait_error_id = wait_task.get('error_id', '')
            if not wait_error_id:
                continue

            try:
                wait_signature = errid_intelligence.extract_coarse_signature(wait_error_id)
                if wait_signature == signature:
                    similar_tasks.append(wait_task)
            except Exception as e:
                logger.warning(f"提取签名失败 | task_id: {wait_task.get('id')} | error: {str(e)}")
                continue

        if not similar_tasks:
            logger.info(f"没有找到相同签名的 wait 任务 | signature: {signature}")
            return

        logger.info(f"找到 {len(similar_tasks)} 个相同签名的 wait 任务，开始批量标记为 verifying")

        # 批量标记为 verifying
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
                    logger.debug(f"任务 {similar_task_id} 标记为 verifying，关联成功任务 {task_id}")
                else:
                    failed_count += 1
                    logger.warning(f"任务 {similar_task_id} 标记失败")

            except Exception as e:
                failed_count += 1
                logger.error(f"标记任务 {similar_task.get('id', 'unknown')} 失败: {str(e)}")

        logger.info(f"批量标记完成 | 成功: {success_count} | 失败: {failed_count} | 关联成功任务: {task_id}")

    except Exception as e:
        logger.error(f"处理相似任务失败: {str(e)}")
        logger.error(traceback.format_exc())


def mark_introduced_errid_tasks_for_verification(client, successful_task: Dict):
    """
    当任务成功时，批量标记 introduced_errids 中的 wait 任务为 verifying

    仅处理构建任务（只有构建任务有 introduced_errids）

    Args:
        client: ManticoreClient 实例
        successful_task: 已成功的任务信息（包含 id, category, j.introduced_errids 等字段）
    """
    try:
        task_id = successful_task.get('id')
        category = successful_task.get('category', 'function')

        # 只处理构建任务
        if category != 'build':
            logger.debug(f"任务 {task_id} 不是构建任务，跳过 introduced_errids 处理 | category: {category}")
            return

        # 从 j 字段读取 introduced_errids
        j_field = successful_task.get('j') or {}
        if isinstance(j_field, str):
            try:
                j_field = json.loads(j_field) if j_field else {}
            except:
                j_field = {}

        introduced_errids = j_field.get('introduced_errids', [])

        if not introduced_errids:
            logger.debug(f"任务 {task_id} 没有 introduced_errids，跳过")
            return

        if not isinstance(introduced_errids, list):
            logger.warning(f"任务 {task_id} 的 introduced_errids 不是列表: {type(introduced_errids)}")
            return

        logger.info(f"任务 {task_id} 成功，开始查找 introduced_errids 匹配的 wait 任务 | errids: {len(introduced_errids)}")

        # 查询所有 wait 状态的构建任务
        query = """
            SELECT id, error_id, bad_job_id, git_url, submit_time, priority_level
            FROM bisect
            WHERE bisect_status = 'wait' AND category = 'build'
            LIMIT 2000
        """

        wait_tasks = client.sql_select(query)

        if not wait_tasks:
            logger.info(f"没有找到 wait 状态的构建任务")
            return

        # 客户端过滤：找到 error_id 在 introduced_errids 列表中的任务
        matched_tasks = []
        for wait_task in wait_tasks:
            wait_error_id = wait_task.get('error_id', '')
            if not wait_error_id:
                continue

            if wait_error_id in introduced_errids:
                matched_tasks.append(wait_task)

        if not matched_tasks:
            logger.info(f"没有找到匹配 introduced_errids 的 wait 任务 | errids: {len(introduced_errids)}")
            return

        logger.info(f"找到 {len(matched_tasks)} 个匹配 introduced_errids 的 wait 任务，开始批量标记为 verifying")

        # 批量标记为 verifying
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
                    logger.debug(f"任务 {matched_task_id} 标记为 verifying，关联成功任务 {task_id}")
                else:
                    failed_count += 1
                    logger.warning(f"任务 {matched_task_id} 标记失败")

            except Exception as e:
                failed_count += 1
                logger.error(f"标记任务 {matched_task.get('id', 'unknown')} 失败: {str(e)}")

        logger.info(f"批量标记完成（introduced_errids）| 成功: {success_count} | 失败: {failed_count} | 关联成功任务: {task_id}")

    except Exception as e:
        logger.error(f"处理 introduced_errids 任务失败: {str(e)}")
        logger.error(traceback.format_exc())