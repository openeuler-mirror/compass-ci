#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
生产者统计报告生成器

将生产者运行结果生成清晰易读的分步骤报告
"""

import os
import json
import time
from datetime import datetime
from pathlib import Path
from typing import Dict
from log_config import logger


class ProducerReporter:
    """生产者报告生成器"""

    def __init__(self, stats_dir: str = None):
        """
        初始化报告生成器

        Args:
            stats_dir: 统计目录路径，默认为 /result/bisect/producer_stats
        """
        if stats_dir is None:
            result_dir = os.environ.get('RESULT_DIR', '/result/bisect')
            stats_dir = os.path.join(result_dir, 'producer_stats')

        self.stats_base_dir = stats_dir
        os.makedirs(stats_dir, exist_ok=True)

    def generate_report(self, stats: Dict, duration: float) -> str:
        """
        生成清晰的分步骤统计报告

        Args:
            stats: 统计数据字典
            duration: 执行时长（秒）

        Returns:
            报告内容字符串
        """
        lines = []
        lines.append("=" * 100)
        lines.append("                          BISECT 任务生产者运行报告")
        lines.append("=" * 100)
        lines.append("")

        # 基本信息
        cycle_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stats.get('cycle_start_time', time.time())))
        lines.append(f"运行时间: {cycle_time}")
        lines.append(f"执行耗时: {duration:.2f} 秒")
        lines.append(f"时间范围: 最近 {stats.get('time_range_hours', 48)} 小时")
        lines.append("")
        lines.append("=" * 100)
        lines.append("")

        # Phase 1: 候选任务收集与智能筛选
        lines.append("Phase 1: 候选任务收集与智能筛选")
        lines.append("-" * 100)
        lines.append(f"  查询时间范围: {stats.get('query_time_from', 'N/A')} → {stats.get('query_time_to', 'N/A')}")
        lines.append(f"  查询到的 jobs 数量: {stats.get('jobs_queried', 0)} 个")
        lines.append(f"  缓存命中(已处理过): {stats.get('jobs_cache_hit', 0)} 个")
        lines.append(f"  ✓ 需要处理的 jobs: {stats.get('jobs_processed', 0)} 个")
        lines.append("")

        # 智能筛选结果
        lines.append("  智能筛选结果:")
        lines.append("  -" * 50)

        # 新增：构建任务过滤统计
        build_filtered = stats.get('build_tasks_filtered', 0)
        if build_filtered > 0:
            lines.append(f"  预处理过滤:")
            lines.append(f"    - 非内核仓库的包构建任务（makepkg）: {build_filtered} 个")
            lines.append("")

        total_before = stats.get('total_errids_before_filter', 0)
        total_after = stats.get('total_errids_after_smart_filter', 0)
        filtered_count = total_before - total_after

        lines.append(f"  筛选前错误总数: {total_before} 个")
        lines.append(f"  智能筛选后保留: {total_after} 个")
        lines.append(f"  过滤掉的噪音: {filtered_count} 个")

        if total_before > 0:
            filter_rate = (filtered_count / total_before) * 100
            lines.append(f"  ✓ 筛选效率: {filter_rate:.1f}% （保留高质量错误 {total_after}/{total_before}）")
        lines.append("")

        # Phase 1.1: 筛选方法统计
        lines.append("  筛选方法分布:")
        smart_count = stats.get('filter_method_smart', 0)
        none_count = stats.get('filter_method_none', 0)
        lines.append(f"    - 智能筛选成功: {smart_count} 个 job")
        lines.append(f"    - 完全过滤掉(无高质量错误): {none_count} 个 job")
        lines.append("")

        # Phase 2: 批量去重检查
        lines.append("Phase 2: 批量去重检查")
        lines.append("-" * 100)
        db_duplicate = stats.get('tasks_db_duplicate', 0)
        no_git_url = stats.get('tasks_no_git_url', 0)
        old_commits = stats.get('tasks_filtered_old_commits', 0)
        created_success = stats.get('tasks_created_success', 0)
        created_failed = stats.get('tasks_created_failed', 0)
        total_candidates = db_duplicate + no_git_url + old_commits + created_success + created_failed

        lines.append(f"  批量去重检查候选: {total_candidates} 个")
        lines.append(f"  数据库已存在(跳过): {db_duplicate} 个")
        lines.append(f"  缺少 git_url(跳过): {no_git_url} 个")

        # Commit 过滤详细统计
        commit_checked = stats.get('tasks_commit_age_checked', 0)
        commit_not_found = stats.get('tasks_commit_hash_not_found', 0)
        total_commit_filtered = old_commits + commit_not_found  # 总过滤数
        if old_commits > 0 or commit_checked > 0 or commit_not_found > 0:
            max_age = stats.get('max_commit_age_days', 365)
            lines.append(f"  Commit 过滤 (共过滤 {total_commit_filtered} 个):")
            lines.append(f"    - 实际检查年龄: {commit_checked} 个")
            lines.append(f"    - 无 commit hash 被过滤: {commit_not_found} 个")
            lines.append(f"    - 过旧被过滤: {old_commits} 个 (超过 {max_age} 天)")
            if commit_checked > 0:
                filter_rate = (old_commits / commit_checked) * 100
                lines.append(f"    - 年龄过滤率: {filter_rate:.1f}% ({old_commits}/{commit_checked})")


        if total_candidates > 0:
            dedup_rate = (db_duplicate / total_candidates) * 100
            lines.append(f"  ✓ 去重率: {dedup_rate:.1f}%")
        lines.append("")

        # Phase 3: 批量任务创建
        lines.append("Phase 3: 批量任务创建")
        lines.append("-" * 100)
        lines.append(f"  创建成功: {created_success} 个")
        lines.append(f"  创建失败: {created_failed} 个")

        # 批量插入统计
        batch_stats = stats.get('batch_insert_stats', {})
        if batch_stats:
            lines.append(f"  批量插入批次: {batch_stats.get('batch_count', 0)}")
            lines.append(f"  批量插入成功率: {batch_stats.get('success_rate', 0):.1f}%")
        lines.append("")

        # 最终结果
        lines.append("=" * 100)
        lines.append("                                   最终结果")
        lines.append("=" * 100)

        processed = stats.get('jobs_processed', 0)
        success_rate = (created_success / processed * 100) if processed > 0 else 0

        lines.append(f"  ✅ 处理的 jobs 总数: {processed}")
        lines.append(f"  ✅ 成功创建任务数: {created_success}")
        lines.append(f"  ✅ 任务转化率: {success_rate:.1f}%")
        lines.append("")

        # 配置参数（附加信息）
        lines.append("-" * 100)
        lines.append("筛选配置参数:")
        lines.append(f"  每个 job 最大错误数: {stats.get('max_count', 6)}")
        lines.append(f"  最低优先级阈值: {stats.get('min_priority', 10)}")
        lines.append("")

        # 性能指标
        lines.append("-" * 100)
        lines.append("性能指标:")
        lines.append(f"  缓存命中率: {stats.get('cache_hit_rate', 0):.2%}")
        lines.append(f"  缓存大小: {stats.get('cache_size', 0)}/{stats.get('cache_max_size', 5000)}")

        if stats.get('jobs_processed', 0) > 0:
            lines.append(f"  平均处理时间:")
            lines.append(f"    - 构建任务过滤: {stats.get('avg_filter_time_ms', 0):.2f}ms")
            lines.append(f"    - Git URL 提取: {stats.get('avg_git_url_time_ms', 0):.2f}ms")
            lines.append(f"    - 错误ID筛选: {stats.get('avg_errid_time_ms', 0):.2f}ms")
        lines.append("")

        # 数据健康度分析
        lines.append("-" * 100)
        lines.append("系统健康度分析:")

        # 筛选效率评估
        if total_before > 0:
            filter_rate = (filtered_count / total_before) * 100
            if filter_rate > 85:
                lines.append(f"  🟢 筛选效率: 优秀 ({filter_rate:.1f}%) - 有效过滤噪音")
            elif filter_rate > 70:
                lines.append(f"  🟡 筛选效率: 良好 ({filter_rate:.1f}%)")
            else:
                lines.append(f"  🔴 筛选效率: 较低 ({filter_rate:.1f}%) - 可能需要调整筛选规则")

        # 去重率评估
        if total_candidates > 0:
            dedup_rate = (db_duplicate / total_candidates) * 100
            if dedup_rate > 95:
                lines.append(f"  🟢 去重率: 优秀 ({dedup_rate:.1f}%) - 系统成熟，重复任务少")
            elif dedup_rate > 80:
                lines.append(f"  🟡 去重率: 良好 ({dedup_rate:.1f}%)")
            else:
                lines.append(f"  🟢 去重率: 正常 ({dedup_rate:.1f}%) - 发现较多新任务")

        # 转化率评估
        if processed > 0:
            if success_rate > 5:
                lines.append(f"  🟢 转化率: 正常 ({success_rate:.1f}%) - 发现较多新问题")
            elif success_rate > 0.5:
                lines.append(f"  🟢 转化率: 健康 ({success_rate:.1f}%) - 系统成熟稳定")
            else:
                lines.append(f"  🟢 转化率: 稳定 ({success_rate:.1f}%) - 极少新问题（成熟系统正常状态）")

        # git_url 缺失警告
        if no_git_url > 0:
            lines.append(f"  ⚠️  发现 {no_git_url} 个任务缺少 git_url，建议检查")

        lines.append("")
        lines.append("=" * 100)
        lines.append(f"报告生成时间: {time.strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append("=" * 100)

        return "\n".join(lines)

    def write_report(self, stats: Dict, duration: float):
        """
        生成并写入报告到 producer_stats 目录（按日期组织）

        Args:
            stats: 统计数据字典
            duration: 执行时长（秒）
        """
        # 生成报告内容
        report_content = self.generate_report(stats, duration)

        # 打印到日志
        logger.info("\n" + report_content)

        # 按日期创建子目录
        cycle_time = stats.get('cycle_start_time', int(time.time()))
        date_str = datetime.fromtimestamp(cycle_time).strftime('%Y-%m-%d')
        daily_dir = os.path.join(self.stats_base_dir, date_str)
        os.makedirs(daily_dir, exist_ok=True)

        # 写入文本文件
        try:
            report_file = os.path.join(
                daily_dir,
                f"producer_report_{cycle_time}.txt"
            )

            with open(report_file, 'w', encoding='utf-8') as f:
                f.write(report_content)

            logger.info(f"✓ 报告已保存至: {report_file}")

        except Exception as e:
            logger.error(f"✗ 写入报告文件失败: {str(e)}")

        # 写入 JSON 数据（用于程序化分析）
        try:
            json_file = os.path.join(
                daily_dir,
                f"producer_stats_{cycle_time}.json"
            )

            with open(json_file, 'w', encoding='utf-8') as f:
                json.dump(stats, f, indent=2, ensure_ascii=False)

            logger.info(f"✓ 统计数据已保存至: {json_file}")

        except Exception as e:
            logger.error(f"✗ 写入统计数据失败: {str(e)}")

    def write_simple_summary(self, stats: Dict):
        """
        写入简短的最新状态摘要到根目录（用于快速查看）

        Args:
            stats: 统计数据字典
        """
        try:
            summary_file = os.path.join(self.stats_base_dir, "producer_latest.txt")

            cycle_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stats.get('cycle_start_time', time.time())))
            processed = stats.get('jobs_processed', 0)
            created = stats.get('tasks_created_success', 0)
            success_rate = (created / processed * 100) if processed > 0 else 0

            summary = f"""最近一次生产者运行状态
=====================
运行时间: {cycle_time}
处理 jobs: {processed}
创建任务: {created}
转化率: {success_rate:.1f}%
=====================
"""

            with open(summary_file, 'w', encoding='utf-8') as f:
                f.write(summary)

            logger.info(f"✓ 最新状态摘要已更新: {summary_file}")

        except Exception as e:
            logger.error(f"✗ 写入状态摘要失败: {str(e)}")
