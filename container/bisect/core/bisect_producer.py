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
from typing import Dict, Any, List, Set, Tuple
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
            logger.info(f"Commit 年龄过滤已启用 | 服务: {commit_service_url} | 最大年龄: {self.max_commit_age_days} 天")
        else:
            self.commit_client = None
            logger.warning("Commit 年龄过滤未启用 (服务不可用)")

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
            kernel_test_script = os.path.join(lkp_src, 'programs/bisect-py/kernel-ci/daily_kernel_test.sh')
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

        # Phase 1: 批量检查 commit 年龄（关键优化：一次网络调用）
        valid_job_ids = set(job_info_map.keys())  # 默认全部有效

        if self.commit_client and commit_check_items:
            logger.info(f"Phase 1: 批量检查 {len(commit_check_items)} 个 commit 年龄...")
            commit_age_start = time.time()

            try:
                too_old_job_ids, checked_valid_ids = self.commit_client.batch_check_commits(
                    commit_check_items,
                    self.max_commit_age_days
                )

                stats['tasks_commit_age_checked'] = len(commit_check_items)
                stats['tasks_filtered_old_commits'] = len(too_old_job_ids)

                # 从有效列表中移除旧 commit 的 job
                valid_job_ids -= too_old_job_ids

                # 记录过滤掉的 job
                for job_id in too_old_job_ids:
                    if job_id in job_info_map:
                        info = job_info_map[job_id]
                        commit = info.get('commit', '')
                        logger.info(f"过滤旧 commit | job_id: {job_id} | commit: {commit[:12] if len(commit) > 12 else commit}... | 超过 {self.max_commit_age_days} 天")
                        del job_info_map[job_id]

            except Exception as e:
                logger.warning(f"批量 commit 检查失败: {str(e)} | 继续处理所有 job")

            stats.setdefault('commit_age_check_time_ms', 0)
            stats['commit_age_check_time_ms'] = (time.time() - commit_age_start) * 1000
            logger.info(f"Phase 1 完成: 过滤 {stats['tasks_filtered_old_commits']} 个旧 commit, 剩余 {len(valid_job_ids)} 个有效 job")
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
    """性能类型bisect任务生产者"""
    
    def __init__(self, client: ManticoreClient, config: Dict):
        self.client = client
        self.config = config
        self.last_run_time = 0
        self.producer_interval = 7 * 86400  # 7天
    
    def execute_producer_cycle(self):
        """执行一个完整的性能类型producer周期 - 目前为占位实现"""
        # 目前返回0，等待实际的性能回归检测逻辑
        logger.info("性能类型生产者：暂未实现具体逻辑，跳过执行")
        return 0
