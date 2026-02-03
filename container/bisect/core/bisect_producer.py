#!/usr/bin/env python3
"""
Bisect Producer - 处理bisect任务的生产者组件
将原TaskProcessor中的生产者相关方法拆分出来
"""

import os
import time
import json
import logging
import shutil
import traceback
import re
import subprocess
from typing import Dict, Any, List, Set, Tuple, Optional
from pathlib import Path
from collections import defaultdict

from manticore_simple import ManticoreClient

# Import project's structured logging system
import sys
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger
from config import Config  # 导入配置类
from bisect_utils import (
    smart_split_error_ids,
    extract_git_url_from_full_text_kv,
    extract_commit_from_full_text_kv,
    get_repo_info_from_job_data,
    write_analysis_files
)

# Import core functions from bisect_utils
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from bisect_utils import extract_repo_name_from_url, categorize_bisect_task, format_error_ids
from producer_reporter import ProducerReporter
from lru_cache import LRUCache  # 使用新的 LRU 缓存
from batch_inserter import BatchInserter  # 导入批量插入器

# Import Commit Time Service Client
sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/services/commit_time_service')
try:
    from client import CommitTimeClient
    COMMIT_TIME_CLIENT_AVAILABLE = True
except ImportError:
    logger.warning("Commit Time Service Client not available, commit age filtering disabled")
    COMMIT_TIME_CLIENT_AVAILABLE = False

class ErrorBisectProducer:
    """错误类型bisect任务生产者"""

    def __init__(self, client: ManticoreClient, config: Dict):
        self.client = client
        self.config = config
        # 使用 LRU 缓存替代简单的 Set
        self.processed_jobs_cache = LRUCache(max_size=5000)
        self.processed_jobs_cache = LRUCache(max_size=5000)
        self.last_run_time = 0
        self.last_metrics_date = None
        self.last_kernel_test_date = None

        # Import intelligent filter
        from errid_intelligence import ErridIntelligence
        self.errid_intelligence = ErridIntelligence()

        # Initialize reporter (使用默认的 producer_stats 目录)
        self.reporter = ProducerReporter()

        # 初始化批量插入器，使用配置的批次大小
        batch_size = Config.BISECT_PRODUCER_BATCH_SIZE
        self.batch_inserter = BatchInserter(client, batch_size=batch_size)

        # 使用配置的查询时间范围
        self.query_hours = Config.BISECT_PRODUCER_QUERY_HOURS
        logger.info(f"ErrorBisectProducer 初始化 | 查询时间范围: {self.query_hours} 小时 | 批次大小: {batch_size}")

        # 初始化 commit time 过滤客户端
        if COMMIT_TIME_CLIENT_AVAILABLE:
            commit_service_url = config.get(
                'commit_time_service_url',
                os.environ.get('COMMIT_TIME_SERVICE_URL', 'http://localhost:8765')
            )
            self.commit_client = CommitTimeClient(commit_service_url)
            self.max_commit_age_days = config.get(
                'max_commit_age_days',
                int(os.environ.get('BISECT_MAX_COMMIT_AGE_DAYS', '365'))
            )
            # 新增：最小内核版本过滤
            self.min_kernel_version = Config.BISECT_MIN_KERNEL_VERSION
            if self.min_kernel_version:
                logger.info(f"Commit 过滤已启用 | 服务: {commit_service_url} | 最大年龄: {self.max_commit_age_days} 天 | 最小版本: v{self.min_kernel_version}")
            else:
                logger.info(f"Commit 年龄过滤已启用 | 服务: {commit_service_url} | 最大年龄: {self.max_commit_age_days} 天 | 版本过滤: 禁用")
        else:
            self.commit_client = None
            self.min_kernel_version = None
            logger.warning("Commit 过滤未启用 (服务不可用)")

    def _run_script(self, script_path, args=None, description="script"):
        """通用脚本执行方法 - 实时流式输出日志"""
        if not os.path.exists(script_path):
            logger.warning(f"{description} not found at: {script_path}")
            return False
            
        logger.info(f"Running {description}: {script_path}")

        # 根据脚本类型构建命令
        if script_path.endswith('.py'):
            # Python 脚本：使用 sys.executable
            cmd = [sys.executable, "-u", script_path]  # -u for unbuffered output
        elif script_path.endswith('.sh'):
            # Shell 脚本：使用 bash 执行避免权限问题
            cmd = ['bash', script_path]
        else:
            # 其他类型：尝试直接执行
            cmd = [script_path]

        # 添加参数
        if args is not None:
            cmd.extend(args)

        try:
            # 使用 Popen 实时获取输出
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,  # 合并 stderr 到 stdout
                text=True,
                bufsize=1,  # 行缓冲
                universal_newlines=True
            )
            
            # 实时读取输出
            for line in process.stdout:
                line = line.strip()
                if line:
                    logger.info(f"[{description}] {line}")
            
            # 等待进程结束
            process.wait(timeout=3600)
            
            if process.returncode == 0:
                logger.info(f"{description} successful.")
                return True
            else:
                logger.error(f"{description} failed (code {process.returncode})")
                return False
                
        except subprocess.TimeoutExpired:
            process.kill()
            logger.error(f"{description} timed out after 3600s")
            return False
        except Exception as e:
            logger.error(f"Error running {description}: {str(e)}")
            return False

    def execute_producer_cycle(self, force_run_scripts=False):
        """
        优化的生产者循环 - 简化版本，主要优化查询
        
        Args:
            force_run_scripts: 是否强制运行维护脚本（忽略每日一次的限制）
        """
        current_date = time.strftime('%Y-%m-%d')
        lkp_src = os.environ.get('LKP_SRC', '/lkp')

        # === 1. 指标收集脚本 ===
        # 每天运行一次，或者强制运行时运行
        if force_run_scripts or self.last_metrics_date != current_date:
            tracker_script = os.path.join(lkp_src, 'programs/bisect-py/utils/bisect_metrics_tracker.py')
            if self._run_script(tracker_script, ['--collect', '--plot'], "metrics collection"):
                # 只有在非强制模式下成功运行才更新日期标记，防止强制运行影响自动调度
                # 或者：无论何时成功都更新？通常强制运行也算作今天的运行。
                # 策略：如果成功运行，就更新日期标记
                self.last_metrics_date = current_date

        # === 2. 每日内核测试脚本 ===
        # 每天运行一次，或者强制运行时运行
        if force_run_scripts or self.last_kernel_test_date != current_date:
            kernel_test_script = os.path.join(lkp_src, 'sbin/bisect/kernel_ci/daily_kernel_test.sh')
            if self._run_script(kernel_test_script, None, "daily kernel test script"):
                self.last_kernel_test_date = current_date

        start_time = time.time()
        cycle_timestamp = int(start_time)

        # 初始化统计数据（使用配置的查询时间）
        stats = {
            'cycle_start_time': cycle_timestamp,
            'time_range_hours': self.query_hours,  # 使用配置的查询时间
            'max_count': 150,     # 提高限制：每个 job 最多 150 个 error_id
            'min_priority': 35,   # 调整到35以包含有价值的代码警告
            'jobs_queried': 0,
            'jobs_cache_hit': 0,
            'jobs_processed': 0,
            'jobs_filtered_out': 0,
            'total_errids_before_filter': 0,
            'total_errids_after_smart_filter': 0,
            'tasks_db_duplicate': 0,
            'tasks_no_git_url': 0,
            'tasks_filtered_old_commits': 0,  # 被 commit 年龄过滤的任务数
            'tasks_commit_age_checked': 0,    # 实际检查年龄的任务数（新增）
            'tasks_commit_hash_not_found': 0,  # 未能提取 commit hash 的任务数（新增）
            'tasks_created_success': 0,
            'tasks_created_failed': 0,
            'filter_method_smart': 0,
            'filter_method_none': 0,
            'batch_queries_count': 0,
            'individual_queries_saved': 0,
            'batch_query_success_rate': 0
        }

        logger.info(f"==" * 40)
        logger.info(f"错误类型生产者循环开始 | 时间: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(start_time))}")
        logger.info(f"==" * 40)

        # 查询最近的jobs（使用配置的时间范围）
        time_range_hours = self.query_hours  # 使用实例配置
        time_threshold = int(time.time() - time_range_hours * 3600)
        from_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(time_threshold))
        to_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime())
        stats['query_time_from'] = from_time
        stats['query_time_to'] = to_time

        logger.info(f"开始查询jobs表 | 时间范围: {from_time} 至 {to_time}")
        logger.info(f"查询条件: 排除 bisect 中间过程任务 (j.bad_job_id IS NULL)")

        sql_query = f"""
            SELECT id, j.errid, full_text_kv, submit_time
            FROM jobs
            WHERE j.errid IS NOT NULL
            AND j.job_stage = 'finish'
            AND j.job_data_readiness = 'complete'
            AND j.bad_job_id IS NULL
            AND submit_time >= {time_threshold}
            ORDER BY id DESC
            LIMIT 1000
        """

        try:
            result = self.client.sql_select(sql_query)
            stats['jobs_queried'] = len(result) if result else 0
            logger.info(f"查询完成 | 返回 {stats['jobs_queried']} 行结果")
        except Exception as e:
            logger.error(f"查询jobs表失败: {str(e)}")
            self._log_producer_stats(stats, start_time)
            return 0

        if not result:
            logger.warning(f"未找到符合条件的错误类型jobs数据")
            self._log_producer_stats(stats, start_time)
            return 0

        # ===== 核心优化：先批量检查 commit 年龄，再处理 error_ids =====
        all_tasks_to_create = []  # 收集所有待创建的任务
        unfiltered_jobs = []  # 未能筛选的任务列表
        job_data_list = []  # 所有处理的任务
        filtered_results = {}  # 成功筛选的结果 {bad_job_id: [(errid, analysis), ...]}

        # Phase 0: 收集所有 job 的基本信息（用于批量 commit 检查）
        logger.info("Phase 0: 收集 job 基本信息...")
        job_info_map = {}  # {job_id: {'full_text_kv': ..., 'git_url': ..., 'commit': ..., 'errids': ...}}
        commit_check_items = []  # 用于批量检查的列表

        for item in result:
            try:
                if not item.get("id"):
                    continue

                bad_job_id = str(int(item["id"]))
                full_text_kv = item.get("full_text_kv", "")
                errids = item.get("j.errid", [])

                # 收集所有处理的 job 数据
                job_data_list.append({
                    'bad_job_id': bad_job_id,
                    'full_text_kv': full_text_kv,
                    'errid_list': errids
                })

                # 缓存检查
                cache_check_start = time.time()
                if bad_job_id in self.processed_jobs_cache:
                    stats['jobs_cache_hit'] += 1
                    stats.setdefault('cache_check_time_ms', 0)
                    stats['cache_check_time_ms'] += (time.time() - cache_check_start) * 1000
                    continue

                self.processed_jobs_cache.add(bad_job_id)
                stats.setdefault('cache_check_time_ms', 0)
                stats['cache_check_time_ms'] += (time.time() - cache_check_start) * 1000

                # 提取 git_url
                git_url_start = time.time()
                git_url = extract_git_url_from_full_text_kv(full_text_kv)
                stats.setdefault('git_url_extract_time_ms', 0)
                stats['git_url_extract_time_ms'] += (time.time() - git_url_start) * 1000

                if not git_url:
                    stats['tasks_no_git_url'] += 1
                    continue

                # 构建任务过滤
                filter_start = time.time()
                should_filter, filter_reason = self.errid_intelligence.should_filter_build_task(full_text_kv, git_url)
                stats.setdefault('filter_time_ms', 0)
                stats['filter_time_ms'] += (time.time() - filter_start) * 1000

                if should_filter:
                    stats.setdefault('build_tasks_filtered', 0)
                    stats['build_tasks_filtered'] += 1
                    logger.debug(f"过滤构建任务 | job_id: {bad_job_id} | 原因: {filter_reason}")
                    continue

                # 提取 commit hash
                commit_hash = extract_commit_from_full_text_kv(full_text_kv)

                # 保存 job 信息
                job_info_map[bad_job_id] = {
                    'full_text_kv': full_text_kv,
                    'git_url': git_url,
                    'commit': commit_hash,
                    'errids': errids,
                    'item': item
                }

                # 如果有 commit，添加到批量检查列表
                if commit_hash and self.commit_client:
                    commit_check_items.append({
                        'job_id': bad_job_id,
                        'git_url': git_url,
                        'commit': commit_hash
                    })
                elif not commit_hash:
                    stats['tasks_commit_hash_not_found'] += 1
                    unfiltered_jobs.append({
                        'bad_job_id': bad_job_id,
                        'errid_list': [],
                        'reason': 'no_commit_hash',
                        'git_url': git_url,
                        'full_text_kv_sample': full_text_kv[:500] if full_text_kv else ''
                    })
                    # 没有 commit hash 的 job 不处理
                    del job_info_map[bad_job_id]

            except Exception as e:
                logger.error(f"Phase 0 处理 job 时出错: {str(e)}")
                continue

        logger.info(f"Phase 0 完成: 收集 {len(job_info_map)} 个有效 job, {len(commit_check_items)} 个需要检查 commit")

        # Phase 1: 批量检查 commit 年龄和分支版本（关键优化：一次网络调用）
        valid_job_ids = set(job_info_map.keys())  # 默认全部有效

        if self.commit_client and commit_check_items:
            filter_desc = f"年龄>{self.max_commit_age_days}天"
            if self.min_kernel_version:
                filter_desc += f" 或 版本<v{self.min_kernel_version}"
            logger.info(f"Phase 1: 批量检查 {len(commit_check_items)} 个 commit ({filter_desc})...")
            commit_age_start = time.time()

            try:
                too_old_job_ids, checked_valid_ids = self.commit_client.batch_check_commits(
                    commit_check_items,
                    self.max_commit_age_days,
                    self.min_kernel_version  # 新增：传入最小内核版本
                )

                stats['tasks_commit_age_checked'] = len(commit_check_items)
                stats['tasks_filtered_old_commits'] = len(too_old_job_ids)

                # 从有效列表中移除旧 commit 的 job
                valid_job_ids -= too_old_job_ids

                # 记录过滤掉的 job（同时添加到 unfiltered_jobs 以便溯源）
                for job_id in too_old_job_ids:
                    if job_id in job_info_map:
                        info = job_info_map[job_id]
                        commit = info.get('commit', '')
                        git_url = info.get('git_url', '')
                        logger.info(f"过滤 commit | job_id: {job_id} | commit: {commit[:12] if len(commit) > 12 else commit}...")
                        # 记录到 unfiltered_jobs 以便在 analysis 目录中溯源
                        unfiltered_jobs.append({
                            'bad_job_id': job_id,
                            'errid_list': info.get('errids', []),
                            'reason': f'commit_filtered (age>{self.max_commit_age_days}d or version<v{self.min_kernel_version})',
                            'git_url': git_url,
                            'commit': commit,
                            'full_text_kv_sample': info.get('full_text_kv', '')[:500] if info.get('full_text_kv') else ''
                        })
                        del job_info_map[job_id]

            except Exception as e:
                logger.warning(f"批量 commit 检查失败: {str(e)} | 继续处理所有 job")

            stats.setdefault('commit_age_check_time_ms', 0)
            stats['commit_age_check_time_ms'] = (time.time() - commit_age_start) * 1000
            logger.info(f"Phase 1 完成: 过滤 {stats['tasks_filtered_old_commits']} 个 commit, 剩余 {len(valid_job_ids)} 个有效 job")
        else:
            logger.info("Phase 1: 跳过 commit 检查 (无 commit client 或无需检查)")

        # Phase 2: 处理通过 commit 检查的 job 的 error_ids
        logger.info(f"Phase 2: 处理 {len(valid_job_ids)} 个有效 job 的 error_ids...")

        for bad_job_id in valid_job_ids:
            if bad_job_id not in job_info_map:
                continue

            try:
                info = job_info_map[bad_job_id]
                full_text_kv = info['full_text_kv']
                git_url = info['git_url']
                errids = info['errids']

                # 提取和筛选 error IDs
                if not isinstance(errids, list):
                    unfiltered_jobs.append({
                        'bad_job_id': bad_job_id,
                        'errid_list': [],
                        'reason': 'no_errids'
                    })
                    continue

                if not errids:
                    unfiltered_jobs.append({
                        'bad_job_id': bad_job_id,
                        'errid_list': [],
                        'reason': 'empty_errids'
                    })
                    continue

                stats['jobs_processed'] += 1
                stats['total_errids_before_filter'] += len(errids)

                # 智能筛选
                errid_filter_start = time.time()
                smart_candidates = self.errid_intelligence.filter_errids(
                    errids,
                    max_count=stats['max_count'],
                    min_priority=stats['min_priority']
                )
                stats.setdefault('errid_filter_time_ms', 0)
                stats['errid_filter_time_ms'] += (time.time() - errid_filter_start) * 1000

                if not smart_candidates:
                    stats['jobs_filtered_out'] += 1
                    unfiltered_jobs.append({
                        'bad_job_id': bad_job_id,
                        'errid_list': errids,
                        'reason': 'no_smart_filter_match'
                    })
                    continue

                # 收集成功筛选的任务
                filtered_results[bad_job_id] = smart_candidates

                # 收集任务
                for errid, analysis in smart_candidates:
                    all_tasks_to_create.append({
                        'bad_job_id': bad_job_id,
                        'error_id': errid,
                        'git_url': git_url,
                        'priority': analysis.priority,
                        'full_text_kv': full_text_kv
                    })

                stats['filter_method_smart'] += 1
                stats['total_errids_after_smart_filter'] += len(smart_candidates)

            except Exception as e:
                logger.error(f"Phase 2 处理 job 时出错: {str(e)}")
                continue

        logger.info(f"Phase 2 完成: 收集 {len(all_tasks_to_create)} 个候选任务")

        # Phase 3: 一次性批量去重（这是关键优化）
        if all_tasks_to_create:
            logger.info(f"Phase 3: 批量去重检查 {len(all_tasks_to_create)} 个任务...")

            # 提取所有error_ids
            all_error_ids = [task['error_id'] for task in all_tasks_to_create]

            # 一次查询检查所有error_ids（可能需要分批如果太多）
            existing_error_ids = set()
            batch_size = 500  # 每批查询500个

            for i in range(0, len(all_error_ids), batch_size):
                batch = all_error_ids[i:i + batch_size]
                try:
                    query = {
                        "bool": {
                            "must": [
                                {"in": {"error_id": batch}}
                            ]
                        }
                    }
                    # 🔧 提高 limit，确保能获取所有匹配的 error_id
                    # 即使同一个 error_id 有多条记录，我们只需要知道它存在
                    existing = self.client.search(index="bisect", query=query, limit=10000)
                    if existing:
                        for item in existing:
                            if item.get('error_id'):
                                existing_error_ids.add(item['error_id'])
                except Exception as e:
                    logger.error(f"批量检查失败: {str(e)}")

            stats['tasks_db_duplicate'] = len(existing_error_ids)
            logger.info(f"去重完成: {len(existing_error_ids)} 个任务已存在")

            # Phase 4: 准备创建新任务
            tasks_to_create = []
            for task_data in all_tasks_to_create:
                if task_data['error_id'] in existing_error_ids:
                    continue  # 跳过已存在的

                # 准备任务数据
                task = {
                    "bad_job_id": task_data['bad_job_id'],
                    "error_id": task_data['error_id'],
                    "bisect_status": "wait",
                    "git_url": task_data['git_url']
                }

                # 添加分类
                category = categorize_bisect_task(task, task_data['full_text_kv'])
                task["category"] = category

                tasks_to_create.append(task)

            # Phase 4: 使用批量插入器创建任务
            if tasks_to_create:
                logger.info(f"Phase 4: 批量创建 {len(tasks_to_create)} 个新任务...")
                success_count, failed_count = self.batch_inserter.batch_create_tasks(tasks_to_create)

                stats['tasks_created_success'] = success_count
                stats['tasks_created_failed'] = failed_count

                # 获取批量插入器的统计信息
                batch_stats = self.batch_inserter.get_stats()
                stats['batch_insert_stats'] = batch_stats
                logger.info(f"批量创建完成 | 成功: {success_count} | 失败: {failed_count}")

        # 生成分析文件（summary 和 filtered/unfiltered JSON）
        if job_data_list:
            try:
                logger.info("生成分析文件...")
                write_analysis_files(job_data_list, filtered_results, unfiltered_jobs)
                logger.info("分析文件生成完成")
            except Exception as e:
                logger.error(f"生成分析文件失败: {str(e)}")

        # 内存管理优化 - LRU 缓存会自动处理驱逐
        # 不需要手动清理，LRU 已设置了 max_size=5000
        if len(self.processed_jobs_cache) > 4500:
            logger.debug(f"Producer cache size: {len(self.processed_jobs_cache)}, "
                        f"evictions: {self.processed_jobs_cache.evictions}")
            # LRU 缓存会自动驱逐最久未使用的项，无需手动干预

        # 输出统计
        self._log_producer_stats(stats, start_time)
        return stats['tasks_created_success']

    def _log_producer_stats(self, stats: dict, start_time: float):
        """输出详细的生产者统计报告并保存到 notification 目录"""
        duration = time.time() - start_time

        # 添加缓存统计
        cache_stats = self.processed_jobs_cache.get_stats()
        stats['cache_hit_rate'] = cache_stats['hit_rate']
        stats['cache_size'] = cache_stats['size']
        stats['cache_max_size'] = cache_stats['max_size']
        stats['cache_evictions'] = cache_stats['evictions']

        # 计算平均耗时
        if stats.get('jobs_processed', 0) > 0:
            stats['avg_filter_time_ms'] = stats.get('filter_time_ms', 0) / stats['jobs_processed']
            stats['avg_git_url_time_ms'] = stats.get('git_url_extract_time_ms', 0) / stats['jobs_processed']
            stats['avg_errid_time_ms'] = stats.get('errid_filter_time_ms', 0) / stats['jobs_processed']
            if stats.get('commit_age_check_time_ms', 0) > 0:
                stats['avg_commit_age_check_ms'] = stats.get('commit_age_check_time_ms', 0) / stats['jobs_processed']

        # 添加 commit 过滤配置到统计
        if self.commit_client:
            stats['max_commit_age_days'] = self.max_commit_age_days

        # 使用新的报告生成器
        self.reporter.write_report(stats, duration)

        # 写入最新状态摘要
        self.reporter.write_simple_summary(stats)

        # 输出性能日志
        logger.info(f"生产者性能统计 | 总耗时: {duration:.2f}s")
        logger.info(f"  缓存命中率: {stats['cache_hit_rate']:.2%} | 缓存大小: {stats['cache_size']}/{cache_stats['max_size']}")
        if stats.get('jobs_processed', 0) > 0:
            logger.info(f"  平均处理时间 | 过滤: {stats.get('avg_filter_time_ms', 0):.2f}ms | "
                       f"URL提取: {stats.get('avg_git_url_time_ms', 0):.2f}ms | "
                       f"ErridID筛选: {stats.get('avg_errid_time_ms', 0):.2f}ms")
            if stats.get('avg_commit_age_check_ms', 0) > 0:
                logger.info(f"  Commit年龄检查: {stats.get('avg_commit_age_check_ms', 0):.2f}ms")

        # 输出过滤统计
        if stats.get('tasks_filtered_old_commits', 0) > 0:
            logger.info(f"Commit 年龄过滤统计 | 过滤数: {stats['tasks_filtered_old_commits']} | "
                       f"阈值: {self.max_commit_age_days} 天")


class PerformanceBisectProducer:
    """性能类型 bisect 任务生产者

    基于 midpoint 算法对 kernel CI 性能测试结果进行比对，
    识别可 bisect 的性能回归并创建任务。

    Phase 1: 基于 kernel CI 的性能监控
    Phase 2: 基于 KPI 的智能监控（未来扩展）

    指标前缀规范 (参考 lkp-stats-type.md):
    - SmallerBetter: lat, jit, pow, cost, mem
    - BiggerBetter: rate
    - KPI 指标使用大写前缀: LAT, JIT, POW, COST, MEM, RATE
    """

    # 前缀常量 (基于 lkp-stats-type.md 规范)
    SMALLER_BETTER_PREFIXES = {'lat', 'jit', 'pow', 'cost', 'mem'}
    BIGGER_BETTER_PREFIXES = {'rate'}

    def __init__(self, client: ManticoreClient, config: Dict):
        self.client = client
        self.config = config
        self.last_run_time = 0

        # 使用配置
        self.producer_interval = Config.PERFORMANCE_PRODUCER_INTERVAL_DAYS * 86400
        self.query_hours = Config.PERFORMANCE_PRODUCER_QUERY_HOURS
        self.min_samples = Config.PERFORMANCE_MIN_SAMPLES
        self.default_samples = Config.PERFORMANCE_DEFAULT_SAMPLES

        # 性能测试套件
        self.performance_suites = [s.strip() for s in Config.PERFORMANCE_SUITES.split(',')]

        # Baseline 配置 - 与 kernel-ci 的 KERNEL_TEST_CONFIG 对齐
        # 格式: {commit: True} 表示这是一个 baseline commit
        self.baseline_commits = {
            # openEuler OLK-5.10 baseline
            '5.10.0-216.0.0': True,
            # openEuler OLK-6.6 baseline
            '6.6.0-98.0.0': True,
            # linux/linux-next baseline
            'v6.17': True,
        }

        # 加载指标配置
        self.metrics_config = self._load_metrics_config()

        # 初始化批量插入器
        self.batch_inserter = BatchInserter(client, batch_size=50)

        # LRU 缓存用于去重
        self.processed_pairs_cache = LRUCache(max_size=1000)

        # 初始化报告器
        self.reporter = ProducerReporter(stats_dir='performance_producer_stats')

        logger.info(f"PerformanceBisectProducer 初始化 | "
                   f"查询时间范围: {self.query_hours} 小时 | "
                   f"运行间隔: {Config.PERFORMANCE_PRODUCER_INTERVAL_DAYS} 天 | "
                   f"监控套件: {self.performance_suites}")

    def _load_metrics_config(self) -> Dict:
        """加载指标配置（已简化）

        KPI 判断和方向推断现在基于 lkp-stats-type.md 规范的前缀：
        - KPI 指标: 大写前缀 (LAT, RATE, JIT, POW, COST, MEM)
        - 方向: lat/jit/pow/cost/mem = -1, rate = +1

        不再需要从 meta.yaml 或 performance_metrics.yaml 加载配置
        """
        logger.info("使用基于前缀的 KPI 判断 (参考 lkp-stats-type.md)")
        return {}

    def execute_producer_cycle(self) -> int:
        """执行一个完整的性能类型 producer 周期

        Returns:
            创建的任务数
        """
        start_time = time.time()
        stats = self._init_stats()

        logger.info("=" * 80)
        logger.info(f"性能 Bisect 生产者循环开始 | 时间: {time.strftime('%Y-%m-%d %H:%M:%S')}")
        logger.info("=" * 80)

        try:
            # Phase 1: 查询性能测试 jobs
            performance_jobs = self._query_performance_jobs()
            stats['jobs_queried'] = len(performance_jobs)

            if not performance_jobs:
                logger.info("未找到性能测试 jobs")
                self._log_stats(stats, start_time)
                return 0

            logger.info(f"Phase 1 完成: 查询到 {len(performance_jobs)} 个性能测试 jobs")

            # Phase 2: 按 (repo, suite, testbox) 分组
            grouped_jobs = self._group_performance_jobs(performance_jobs)
            stats['groups_found'] = len(grouped_jobs)
            logger.info(f"Phase 2 完成: 分组为 {len(grouped_jobs)} 个组")

            # Phase 3: 识别 baseline/current 配对
            comparison_pairs = self._identify_comparison_pairs(grouped_jobs)
            stats['pairs_found'] = len(comparison_pairs)
            logger.info(f"Phase 3 完成: 识别 {len(comparison_pairs)} 个比较配对")

            # Phase 4: 应用 midpoint 算法筛选可 bisect 的配对
            bisectable_pairs = self._filter_bisectable_pairs(comparison_pairs, stats)
            stats['bisectable_pairs'] = len(bisectable_pairs)
            logger.info(f"Phase 4 完成: {len(bisectable_pairs)} 个配对满足 bisect 条件")

            # Phase 5: 创建 bisect 任务
            tasks_created = self._create_bisect_tasks(bisectable_pairs, stats)
            stats['tasks_created'] = tasks_created
            logger.info(f"Phase 5 完成: 创建 {tasks_created} 个性能 bisect 任务")

            return tasks_created

        except Exception as e:
            logger.error(f"性能生产者循环失败: {str(e)}")
            logger.error(traceback.format_exc())
            return 0
        finally:
            self._log_stats(stats, start_time)

    def _init_stats(self) -> Dict:
        """初始化统计数据"""
        return {
            'cycle_start_time': int(time.time()),
            'time_range_hours': self.query_hours,
            'jobs_queried': 0,
            'groups_found': 0,
            'pairs_found': 0,
            'pairs_cache_hit': 0,
            'pairs_insufficient_samples': 0,
            'pairs_no_gap': 0,
            'pairs_below_threshold': 0,
            'bisectable_pairs': 0,
            'tasks_db_duplicate': 0,
            'tasks_created': 0,
            'tasks_failed': 0
        }

    def _query_performance_jobs(self) -> List[Dict]:
        """查询性能测试 jobs

        查询条件:
        - suite 在监控列表中
        - job_stage = 'finish', job_health = 'success'
        - submit_time 在查询时间范围内
        """
        time_threshold = int(time.time() - self.query_hours * 3600)
        suites_sql = "', '".join(self.performance_suites)

        # 构建查询 - 直接获取 j.ss.linux.commit 字段
        sql_query = f"""
            SELECT id, suite, testbox, submit_time, full_text_kv, j, j.ss.linux.commit as linux_commit
            FROM jobs
            WHERE suite IN ('{suites_sql}')
            AND j.job_stage = 'finish'
            AND j.job_health = 'success'
            AND j.job_data_readiness = 'complete'
            AND submit_time >= {time_threshold}
            ORDER BY submit_time DESC
            LIMIT 5000
        """

        try:
            result = self.client.sql_select(sql_query)
            if not result:
                logger.info(f"SQL 查询返回空结果 | 套件: {self.performance_suites}")
                return []

            logger.info(f"SQL 查询返回 {len(result)} 条原始记录")

            # 解析并提取有效 job 数据
            processed_jobs = []
            parse_failures = {'no_commit': 0, 'no_git_url': 0, 'no_stats': 0, 'other': 0}
            suite_counts = defaultdict(int)

            for item in result:
                job_data = self._parse_job_data(item)
                if job_data:
                    processed_jobs.append(job_data)
                    suite_counts[job_data['suite']] += 1

            # 输出套件分布
            if suite_counts:
                logger.info(f"有效 jobs 按套件分布: {dict(suite_counts)}")
            else:
                logger.warning("未解析到有效的性能测试 jobs")

            return processed_jobs

        except Exception as e:
            logger.error(f"查询性能 jobs 失败: {str(e)}")
            return []

    def _parse_job_data(self, item: Dict) -> Optional[Dict]:
        """解析 job 数据

        提取: commit, git_url, stats, testbox, suite, repo/branch 信息
        """
        try:
            j_field = item.get('j', {})
            if isinstance(j_field, str):
                import json
                j_field = json.loads(j_field)

            full_text_kv = item.get('full_text_kv', '')

            # 提取 commit - 优先使用 SQL 直接返回的 linux_commit
            commit = item.get('linux_commit') or self._extract_commit(j_field, full_text_kv)
            if not commit:
                return None

            # 提取 git_url
            git_url = extract_git_url_from_full_text_kv(full_text_kv)
            if not git_url:
                return None

            # 提取 stats
            stats = j_field.get('stats', {})
            if not stats:
                return None

            # 提取 repo/branch 信息
            repo_name = extract_repo_name_from_url(git_url)
            branch = self._extract_branch(j_field, full_text_kv)

            return {
                'job_id': str(item.get('id')),
                'suite': item.get('suite'),
                'testbox': item.get('testbox', ''),
                'commit': commit,
                'git_url': git_url,
                'repo_name': repo_name,
                'branch': branch or 'master',
                'stats': stats,
                'submit_time': item.get('submit_time'),
                'full_text_kv': full_text_kv,
                'j': j_field
            }

        except Exception as e:
            logger.debug(f"解析 job 数据失败: {str(e)}")
            return None

    def _extract_commit(self, j_field: Dict, full_text_kv: str) -> Optional[str]:
        """提取 commit hash"""
        # 尝试从 j 字段提取
        if j_field:
            # ss.linux.commit
            commit = j_field.get('ss', {}).get('linux', {}).get('commit')
            if commit:
                return commit

            # program.makepkg.commit
            commit = j_field.get('program', {}).get('makepkg', {}).get('commit')
            if commit:
                return commit

        # 尝试从 full_text_kv 提取
        return extract_commit_from_full_text_kv(full_text_kv)

    def _extract_branch(self, j_field: Dict, full_text_kv: str) -> Optional[str]:
        """提取分支信息"""
        if j_field:
            # program.makepkg.branch
            branch = j_field.get('program', {}).get('makepkg', {}).get('branch')
            if branch:
                return branch

        # 从 full_text_kv 提取
        for line in full_text_kv.split('\n'):
            if 'branch' in line.lower():
                parts = line.split(':')
                if len(parts) >= 2:
                    return parts[-1].strip()

        return None

    def _group_performance_jobs(self, jobs: List[Dict]) -> Dict[Tuple, List[Dict]]:
        """按 (repo, suite, testbox) 分组

        分组策略：
        - 保留 repo 区分不同内核仓库 (openeuler-kernel vs linux vs linux-next)
        - 去掉 branch 避免解析错误导致分组过细
        - 性能比较需要在相同硬件(testbox)上才有意义
        """
        groups = defaultdict(list)

        for job in jobs:
            group_key = (
                job['repo_name'],
                job['suite'],
                job['testbox']
            )
            groups[group_key].append(job)

        # 输出分组统计
        if groups:
            # 按 suite 统计组数
            suite_group_counts = defaultdict(int)
            for (repo, suite, testbox), job_list in groups.items():
                suite_group_counts[suite] += 1
            logger.info(f"分组统计 | 按套件: {dict(suite_group_counts)}")

        return dict(groups)

    def _identify_comparison_pairs(self, grouped_jobs: Dict[Tuple, List[Dict]]) -> List[Dict]:
        """识别 baseline/current 比较配对

        策略:
        1. baseline: 稳定版本 tag (v6.17, 5.10.0-216.0.0)
        2. current: RC/HEAD 或动态 tag
        3. baseline 和 current 各需要至少 3 个 jobs 才能进行线性可分验证
        """
        comparison_pairs = []
        skip_reasons = {'no_baseline': 0, 'no_current': 0, 'insufficient_baseline': 0,
                       'insufficient_current': 0, 'no_metrics': 0}
        MIN_JOBS_REQUIRED = 3

        for group_key, jobs in grouped_jobs.items():
            repo_name, suite, testbox = group_key

            # 分离 baseline 和 current jobs
            baseline_jobs = []
            current_jobs = []

            for job in jobs:
                commit = job['commit']
                if self._is_baseline_commit(commit):
                    baseline_jobs.append(job)
                else:
                    current_jobs.append(job)

            if not baseline_jobs:
                skip_reasons['no_baseline'] += 1
                commits = list(set(j['commit'][:16] for j in jobs[:5]))
                logger.info(f"跳过组 {repo_name}/{suite}/{testbox}: 无baseline | commits: {commits}")
                continue

            if not current_jobs:
                skip_reasons['no_current'] += 1
                commits = list(set(j['commit'][:16] for j in jobs[:5]))
                logger.info(f"跳过组 {repo_name}/{suite}/{testbox}: 无current | commits: {commits}")
                continue

            # 检查是否有足够的 baseline jobs
            if len(baseline_jobs) < MIN_JOBS_REQUIRED:
                skip_reasons['insufficient_baseline'] += 1
                logger.info(f"跳过组 {repo_name}/{suite}/{testbox}: baseline jobs 不足 "
                           f"({len(baseline_jobs)}<{MIN_JOBS_REQUIRED})")
                continue

            # 检查是否有足够的 current jobs
            if len(current_jobs) < MIN_JOBS_REQUIRED:
                skip_reasons['insufficient_current'] += 1
                logger.info(f"跳过组 {repo_name}/{suite}/{testbox}: current jobs 不足 "
                           f"({len(current_jobs)}<{MIN_JOBS_REQUIRED})")
                continue

            # 找出所有 jobs 共有的数字指标
            all_jobs = baseline_jobs + current_jobs
            common_metrics = set(all_jobs[0]['stats'].keys())
            for job in all_jobs[1:]:
                common_metrics &= set(job['stats'].keys())

            # 过滤只保留数字类型且以 suite 开头的指标
            valid_metrics = []
            sample_stats = baseline_jobs[0]['stats']
            for metric in common_metrics:
                if not metric.startswith(f"{suite}."):
                    continue
                try:
                    float(sample_stats[metric])
                    valid_metrics.append(metric)
                except (TypeError, ValueError):
                    pass

            if not valid_metrics:
                skip_reasons['no_metrics'] += 1
                logger.info(f"组 {repo_name}/{suite}/{testbox}: 无共有数字指标")
                continue

            # 创建配对：包含所有 baseline jobs 和 current jobs
            baseline_commit = baseline_jobs[0]['commit']
            current_commit = current_jobs[0]['commit']

            comparison_pairs.append({
                'group_key': group_key,
                'metrics': valid_metrics,
                'suite': suite,
                'baseline_jobs': baseline_jobs,  # 多个 baseline jobs
                'current_jobs': current_jobs,    # 多个 current jobs
                'git_url': baseline_jobs[0]['git_url'],
                'baseline_commit': baseline_commit,
                'current_commit': current_commit
            })

            logger.info(f"组 {repo_name}/{suite}/{testbox}: 创建配对 | "
                       f"{len(valid_metrics)} 个指标 | "
                       f"baseline: {baseline_commit[:12]} ({len(baseline_jobs)} jobs) | "
                       f"current: {current_commit[:12]} ({len(current_jobs)} jobs)")

        # 输出跳过原因统计
        if any(skip_reasons.values()):
            logger.info(f"配对跳过统计 | 无baseline: {skip_reasons['no_baseline']} | "
                       f"无current: {skip_reasons['no_current']} | "
                       f"baseline不足: {skip_reasons['insufficient_baseline']} | "
                       f"current不足: {skip_reasons['insufficient_current']} | "
                       f"无共有指标: {skip_reasons['no_metrics']}")

        return comparison_pairs

    def _is_baseline_commit(self, commit: str) -> bool:
        """判断是否为 baseline commit

        使用配置定义的 baseline commits，与 kernel-ci 的 KERNEL_TEST_CONFIG 对齐：
        - baseline: 固定的稳定版本 (5.10.0-216.0.0, 6.6.0-98.0.0, v6.17)
        - current: 动态获取的最新版本 (5.10.0-295.0.0, 6.6.0-132.0.0, v6.18-rc7, next-*)
        """
        # 直接查找配置的 baseline commits
        return commit in self.baseline_commits

    def _filter_bisectable_pairs(self, pairs: List[Dict], stats: Dict) -> List[Dict]:
        """应用 midpoint 算法筛选可 bisect 的配对

        对每个配对中的所有指标进行检查，保留有性能差距的指标

        改进：
        1. 使用数据库查询获取所有可用样本，而不是仅当前周期的 jobs
        2. 波动太大的情况下 midpoint 检查会自然失败，无法 bisect
        """
        bisectable = []

        for pair in pairs:
            try:
                # 获取 testbox (从 group_key 中提取)
                testbox = pair['group_key'][2]

                # 检查缓存
                pair_key = self._generate_pair_key(pair)
                if pair_key in self.processed_pairs_cache:
                    stats['pairs_cache_hit'] += 1
                    continue

                suite = pair['suite']
                baseline_commit = pair['baseline_commit']
                current_commit = pair['current_commit']

                # 遍历所有指标，找出有性能差距的
                metrics_with_gap = []
                for metric in pair['metrics']:
                    # 只处理 KPI 指标（大写前缀）
                    if not self._is_kpi_metric(metric):
                        continue

                    # 从数据库查询所有可用样本（而不是仅当前周期的 jobs）
                    v1_samples = self._query_all_samples_from_db(baseline_commit, suite, testbox, metric)
                    v2_samples = self._query_all_samples_from_db(current_commit, suite, testbox, metric)

                    # 验证样本数量 (至少需要 3 个样本才能进行线性可分验证)
                    if len(v1_samples) < 3 or len(v2_samples) < 3:
                        stats['pairs_insufficient_samples'] += 1
                        continue

                    # 检查性能差距 (midpoint 算法: v1_max < v2_min)
                    has_gap, gap_info = self._check_performance_gap(v1_samples, v2_samples)

                    if has_gap:
                        metrics_with_gap.append({
                            'metric': metric,
                            'gap_info': gap_info,
                            'v1_samples': v1_samples,
                            'v2_samples': v2_samples
                        })

                if not metrics_with_gap:
                    stats['pairs_no_gap'] += 1
                    continue

                # 保留有差距的指标信息
                pair['metrics_with_gap'] = metrics_with_gap
                bisectable.append(pair)

                # 添加到缓存
                self.processed_pairs_cache.add(pair_key)

                # 日志：显示有差距的指标
                for m in metrics_with_gap[:3]:  # 最多显示 3 个
                    logger.info(f"发现可 bisect | {pair['suite']}/{testbox}/{pair['baseline_commit'][:8]}..{pair['current_commit'][:8]} | "
                               f"{m['metric'].split('.')[-1]}: {m['gap_info']['change_percent']:.1f}% | "
                               f"样本数: v1={len(m['v1_samples'])}, v2={len(m['v2_samples'])}")

            except Exception as e:
                logger.warning(f"处理配对时出错: {str(e)}")
                continue

        # 输出筛选统计
        if pairs:
            logger.info(f"Midpoint 筛选统计 | 总配对: {len(pairs)} | "
                       f"缓存命中: {stats['pairs_cache_hit']} | "
                       f"无性能差距: {stats['pairs_no_gap']} | "
                       f"可bisect: {len(bisectable)}")

        return bisectable

    def _generate_pair_key(self, pair: Dict) -> str:
        """生成配对的唯一标识"""
        return f"{pair['baseline_commit']}_{pair['current_commit']}_{pair['suite']}"

    def _collect_samples(self, job: Dict, metric: str) -> List[float]:
        """从单个 job 收集指标样本"""
        samples = []
        stats = job.get('stats', {})

        if metric in stats:
            try:
                value = float(stats[metric])
                samples.append(value)
            except (ValueError, TypeError):
                pass

        return samples

    def _collect_samples_from_list(self, jobs: List[Dict], metric: str) -> List[float]:
        """从多个 jobs 收集指标样本"""
        samples = []

        for job in jobs:
            job_samples = self._collect_samples(job, metric)
            samples.extend(job_samples)

        return samples

    def _query_all_samples_from_db(self, commit: str, suite: str, testbox: str, metric: str) -> List[float]:
        """从数据库查询指定 commit/suite/testbox/metric 的所有样本

        使用所有可用样本来计算 range，确保 midpoint 判断的准确性
        """
        sql = f"""
            SELECT j
            FROM jobs
            WHERE j.ss.linux.commit = '{commit}'
            AND suite = '{suite}'
            AND testbox = '{testbox}'
            AND j.job_stage = 'finish'
            AND j.job_health = 'success'
            AND j.job_data_readiness = 'complete'
            ORDER BY submit_time DESC
            LIMIT 100
        """

        try:
            result = self.client.sql_select(sql)
            if not result:
                return []

            samples = []
            for item in result:
                j = item.get('j', {})
                if isinstance(j, str):
                    try:
                        j = json.loads(j)
                    except json.JSONDecodeError:
                        continue

                stats = j.get('stats', {})
                if metric in stats:
                    try:
                        value = float(stats[metric])
                        samples.append(value)
                    except (ValueError, TypeError):
                        pass

            return samples
        except Exception as e:
            logger.warning(f"查询样本失败: {commit[:8]}/{suite}/{testbox}/{metric} - {e}")
            return []

    def _is_kpi_metric(self, metric: str) -> bool:
        """判断是否为 KPI 指标（大写前缀）

        根据 lkp-stats-type.md 规范:
        - 小写前缀 (lat, rate) = 普通指标
        - 大写前缀 (LAT, RATE) = KPI 指标

        metric 格式: {suite}.{PREFIX}.{name}...
        例如: lmbench.LAT.CTX.8P.64K.latency.us (KPI)
              lmbench.lat.ctx.latency.us (非 KPI)
        """
        parts = metric.split('.')

        # 遍历找到前缀部分
        all_prefixes = self.SMALLER_BETTER_PREFIXES | self.BIGGER_BETTER_PREFIXES
        for part in parts:
            if part.lower() in all_prefixes:
                # 大写 = KPI
                return part.isupper()

        return False

    def _check_performance_gap(self, v1_samples: List[float], v2_samples: List[float]) -> Tuple[bool, Dict]:
        """检查性能样本是否有明确的差距用于 bisect

        Midpoint 算法逻辑:
        - v1_max < v2_min OR v2_max < v1_min
        - 计算 midpoint 作为 bisect 判断阈值
        """
        v1_min, v1_max = min(v1_samples), max(v1_samples)
        v2_min, v2_max = min(v2_samples), max(v2_samples)

        # 检查不重叠的范围
        has_gap = (v1_max < v2_min) or (v2_max < v1_min)

        if not has_gap:
            return False, {}

        # 确定方向并计算 midpoint
        if v1_max < v2_min:
            # 回归: v1 更好 (更小) → v2 更差 (更大)
            mid_point = (v1_max + v2_min) / 2
            direction = 'worse'
            change_percent = ((v2_min - v1_max) / v1_max) * 100 if v1_max != 0 else 0
        else:
            # 改进: v2 更好 (更小) → v1 更差 (更大)
            mid_point = (v2_max + v1_min) / 2
            direction = 'better'
            change_percent = ((v1_min - v2_max) / v2_max) * 100 if v2_max != 0 else 0

        return True, {
            'mid_point': mid_point,
            'direction': direction,
            'v1_range': (v1_min, v1_max),
            'v2_range': (v2_min, v2_max),
            'change_percent': change_percent
        }

    def _create_bisect_tasks(self, bisectable_pairs: List[Dict], stats: Dict) -> int:
        """为可 bisect 的配对创建任务

        每个可 bisect 的指标创建一个独立任务
        """
        if not bisectable_pairs:
            return 0

        tasks_to_create = []

        for pair in bisectable_pairs:
            # 遍历每个有性能差距的指标，为每个指标创建独立任务
            for metric_info in pair.get('metrics_with_gap', []):
                try:
                    metric = metric_info['metric']

                    # 检查该指标的任务是否已存在
                    if self._task_exists_for_metric(pair, metric):
                        stats['tasks_db_duplicate'] += 1
                        continue

                    # 构建任务文档
                    task = self._build_task_document(pair, metric_info)
                    if task:
                        tasks_to_create.append(task)

                except Exception as e:
                    logger.warning(f"创建任务时出错: {str(e)}")
                    stats['tasks_failed'] += 1
                    continue

        if not tasks_to_create:
            return 0

        # 批量插入
        success_count, failed_count = self.batch_inserter.batch_create_tasks(tasks_to_create)

        stats['tasks_failed'] += failed_count
        return success_count

    def _task_exists_for_metric(self, pair: Dict, metric: str) -> bool:
        """检查特定指标的任务是否已存在于数据库"""
        try:
            query = {
                "bool": {
                    "must": [
                        {"equals": {"bisect_metric": metric}},
                        {"equals": {"category": "benchmark"}}
                    ]
                }
            }

            # 检查 baseline 和 current commit
            existing = self.client.search(index="bisect", query=query, limit=10)

            if existing:
                for item in existing:
                    j_field = item.get('j', {})
                    if isinstance(j_field, str):
                        import json
                        j_field = json.loads(j_field)

                    if (j_field.get('baseline_commit') == pair['baseline_commit'] and
                        j_field.get('current_commit') == pair['current_commit']):
                        return True

            return False

        except Exception as e:
            logger.debug(f"检查任务存在性失败: {str(e)}")
            return False

    def _build_task_document(self, pair: Dict, metric_info: Dict) -> Dict:
        """构建 bisect 任务文档

        Args:
            pair: 配对信息 (baseline_job, current_jobs, git_url, suite, commits)
            metric_info: 指标信息 (metric, gap_info, v1_samples, v2_samples)
        """
        metric = metric_info['metric']
        gap_info = metric_info['gap_info']
        v1_samples = metric_info['v1_samples']
        v2_samples = metric_info['v2_samples']

        # good/bad 基于时间顺序，而非性能方向
        # - good_commit: 较旧的 commit (baseline, 祖先)
        # - bad_commit: 较新的 commit (current, 后代)
        # 性能方向 (worse/better) 存储在 performance_change_type 中
        good_commit = pair['baseline_commit']
        bad_job_id = pair['current_jobs'][0]['job_id']

        # 获取指标方向
        metric_direction = self._get_metric_direction(pair['suite'], metric)

        task = {
            'bad_job_id': bad_job_id,
            'bisect_metric': metric,
            'direction': gap_info['direction'],
            'category': 'benchmark',
            'git_url': pair['git_url'],
            'bisect_status': 'wait',
            'submit_time': int(time.time()),
            'j': {
                'good_commit': good_commit,
                'bad_commit': pair['current_commit'],  # 较新的 commit
                'mid_point': gap_info['mid_point'],
                'metric_direction': metric_direction,
                'v1_samples': v1_samples,
                'v2_samples': v2_samples,
                'v1_range': list(gap_info['v1_range']),
                'v2_range': list(gap_info['v2_range']),
                'change_percent': gap_info['change_percent'],
                'performance_change_type': gap_info['direction'],
                'baseline_commit': pair['baseline_commit'],
                'current_commit': pair['current_commit'],
                'suite': pair['suite'],
                'testbox': pair['group_key'][2],  # group_key = (repo_name, suite, testbox)
                'source': 'performance_producer',
                'created_at': int(time.time())
            }
        }

        return task

    def _get_metric_direction(self, suite: str, metric: str) -> int:
        """获取指标的优化方向（基于前缀规范）

        根据 lkp-stats-type.md 规范，从 metric 前缀推断方向：
        - lat/jit/pow/cost/mem 前缀: -1 (SmallerBetter)
        - rate 前缀: +1 (BiggerBetter)

        +1 = 越大越好 (throughput, IOPS, bandwidth)
        -1 = 越小越好 (latency, jitter, power)

        metric 格式: {suite}.{PREFIX}.{name}...
        例如: lmbench.LAT.CTX.8P.64K.latency.us
        """
        # 提取前缀：跳过 suite 部分
        # metric 可能是 "LAT.CTX.8P.64K.latency.us" 或 "lmbench.LAT.CTX.8P.64K.latency.us"
        parts = metric.split('.')

        # 找到前缀位置
        prefix = None
        for part in parts:
            part_lower = part.lower()
            if part_lower in self.SMALLER_BETTER_PREFIXES or part_lower in self.BIGGER_BETTER_PREFIXES:
                prefix = part_lower
                break

        if prefix:
            if prefix in self.SMALLER_BETTER_PREFIXES:
                return -1
            if prefix in self.BIGGER_BETTER_PREFIXES:
                return 1

        # 回退：根据指标名称关键词猜测
        metric_lower = metric.lower()
        if any(kw in metric_lower for kw in ['lat', 'time', 'latency', 'jit', 'cost']):
            return -1
        if any(kw in metric_lower for kw in ['throughput', 'iops', 'bw', 'bandwidth', 'rate', 'score']):
            return 1

        return 0  # 未知

    def _log_stats(self, stats: Dict, start_time: float):
        """输出统计报告"""
        duration = time.time() - start_time

        logger.info("=" * 80)
        logger.info("性能 Bisect 生产者统计报告")
        logger.info("=" * 80)
        logger.info(f"总耗时: {duration:.2f}s")
        logger.info(f"查询时间范围: {stats['time_range_hours']} 小时")
        logger.info(f"查询 jobs 数: {stats['jobs_queried']}")
        logger.info(f"分组数: {stats['groups_found']}")
        logger.info(f"比较配对数: {stats['pairs_found']}")
        logger.info(f"  - 缓存命中: {stats['pairs_cache_hit']}")
        logger.info(f"  - 样本不足: {stats['pairs_insufficient_samples']}")
        logger.info(f"  - 无性能差距: {stats['pairs_no_gap']}")
        logger.info(f"  - 低于阈值: {stats['pairs_below_threshold']}")
        logger.info(f"可 bisect 配对: {stats['bisectable_pairs']}")
        logger.info(f"任务创建: {stats['tasks_created']}")
        logger.info(f"  - 数据库重复: {stats['tasks_db_duplicate']}")
        logger.info(f"  - 创建失败: {stats['tasks_failed']}")
        logger.info("=" * 80)

        # 使用报告器保存详细统计
        try:
            self.reporter.write_report(stats, duration)
        except Exception as e:
            logger.debug(f"保存统计报告失败: {str(e)}")

