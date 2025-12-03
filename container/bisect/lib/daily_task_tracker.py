#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
每日任务统计追踪器

追踪每天创建和完成的bisect任务数量，生成趋势报告。
"""

import json
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from collections import defaultdict

from log_config import logger


class DailyTaskTracker:
    """
    追踪每日任务的创建和完成情况
    """

    def __init__(self, stats_dir: str = "/result/bisect/daily_stats"):
        """
        初始化每日统计追踪器

        Args:
            stats_dir: 统计数据存储目录
        """
        self.stats_dir = Path(stats_dir)
        self.stats_dir.mkdir(parents=True, exist_ok=True)

        # 当天统计文件
        today = datetime.now().strftime("%Y-%m-%d")
        self.today_file = self.stats_dir / f"{today}.json"

        # 加载或初始化当天统计
        self.today_stats = self._load_today_stats()

    def _load_today_stats(self) -> Dict:
        """加载当天的统计数据"""
        if self.today_file.exists():
            try:
                with open(self.today_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"加载统计文件失败: {e}")

        # 初始化新的统计数据
        return {
            'date': datetime.now().strftime("%Y-%m-%d"),
            'created': 0,
            'completed': 0,
            'failed': 0,
            'in_progress': 0,
            'hourly_created': defaultdict(int),
            'hourly_completed': defaultdict(int),
            'error_categories': defaultdict(int),
            'repositories': defaultdict(int),
            'last_update': None
        }

    def record_task_created(self, count: int = 1, category: str = None, repo: str = None):
        """
        记录创建的任务

        Args:
            count: 创建的任务数
            category: 任务分类
            repo: 仓库名称
        """
        hour = datetime.now().strftime("%H")

        self.today_stats['created'] += count
        self.today_stats['hourly_created'][hour] = \
            self.today_stats['hourly_created'].get(hour, 0) + count

        if category:
            self.today_stats['error_categories'][category] = \
                self.today_stats['error_categories'].get(category, 0) + count

        if repo:
            self.today_stats['repositories'][repo] = \
                self.today_stats['repositories'].get(repo, 0) + count

        self._save_stats()

    def record_task_completed(self, count: int = 1):
        """记录完成的任务"""
        hour = datetime.now().strftime("%H")

        self.today_stats['completed'] += count
        self.today_stats['hourly_completed'][hour] = \
            self.today_stats['hourly_completed'].get(hour, 0) + count

        self._save_stats()

    def record_task_failed(self, count: int = 1):
        """记录失败的任务"""
        self.today_stats['failed'] += count
        self._save_stats()

    def update_in_progress(self, count: int):
        """更新进行中的任务数"""
        self.today_stats['in_progress'] = count
        self._save_stats()

    def _save_stats(self):
        """保存统计数据到文件"""
        self.today_stats['last_update'] = datetime.now().isoformat()

        try:
            with open(self.today_file, 'w') as f:
                json.dump(self.today_stats, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logger.error(f"保存统计文件失败: {e}")

    def get_daily_summary(self, days: int = 7) -> List[Dict]:
        """
        获取最近几天的统计摘要

        Args:
            days: 统计天数

        Returns:
            每日统计列表
        """
        summaries = []

        for i in range(days):
            date = datetime.now() - timedelta(days=i)
            date_str = date.strftime("%Y-%m-%d")
            stats_file = self.stats_dir / f"{date_str}.json"

            if stats_file.exists():
                try:
                    with open(stats_file, 'r') as f:
                        summaries.append(json.load(f))
                except Exception as e:
                    logger.error(f"读取 {date_str} 统计失败: {e}")

        return sorted(summaries, key=lambda x: x['date'], reverse=True)

    def generate_trend_report(self, days: int = 7) -> str:
        """
        生成趋势报告

        Args:
            days: 统计天数

        Returns:
            格式化的趋势报告
        """
        summaries = self.get_daily_summary(days)

        if not summaries:
            return "暂无统计数据"

        report = []
        report.append("=" * 80)
        report.append(f"Bisect 任务趋势报告（最近 {days} 天）")
        report.append("=" * 80)
        report.append("")

        # 总体统计
        total_created = sum(s.get('created', 0) for s in summaries)
        total_completed = sum(s.get('completed', 0) for s in summaries)
        total_failed = sum(s.get('failed', 0) for s in summaries)

        report.append("【总体统计】")
        report.append(f"  总创建任务: {total_created}")
        report.append(f"  总完成任务: {total_completed}")
        report.append(f"  总失败任务: {total_failed}")
        report.append(f"  完成率: {total_completed/total_created*100:.1f}%" if total_created > 0 else "  完成率: N/A")
        report.append("")

        # 每日明细
        report.append("【每日明细】")
        report.append("日期       | 创建 | 完成 | 失败 | 进行中 | 完成率")
        report.append("-" * 60)

        for summary in summaries:
            date = summary['date']
            created = summary.get('created', 0)
            completed = summary.get('completed', 0)
            failed = summary.get('failed', 0)
            in_progress = summary.get('in_progress', 0)
            completion_rate = f"{completed/created*100:.1f}%" if created > 0 else "N/A"

            report.append(f"{date} | {created:4} | {completed:4} | {failed:4} | {in_progress:6} | {completion_rate:>7}")

        # 趋势分析
        if len(summaries) >= 2:
            report.append("")
            report.append("【趋势分析】")

            # 计算日均
            avg_created = total_created / len(summaries)
            avg_completed = total_completed / len(summaries)

            report.append(f"  日均创建: {avg_created:.1f} 个任务")
            report.append(f"  日均完成: {avg_completed:.1f} 个任务")

            # 计算增长率（对比最近两天）
            if summaries[0]['created'] > 0 and summaries[1]['created'] > 0:
                growth = (summaries[0]['created'] - summaries[1]['created']) / summaries[1]['created'] * 100
                report.append(f"  创建量环比: {growth:+.1f}%")

        # 热门仓库（如果有数据）
        if summaries and 'repositories' in summaries[0] and summaries[0]['repositories']:
            report.append("")
            report.append("【今日热门仓库】")
            repos = sorted(summaries[0]['repositories'].items(), key=lambda x: x[1], reverse=True)[:5]
            for repo, count in repos:
                report.append(f"  - {repo}: {count} 个任务")

        report.append("")
        report.append("=" * 80)

        return "\n".join(report)

    def get_current_stats(self) -> Dict:
        """获取当前统计数据"""
        return self.today_stats.copy()


# 全局实例
_daily_tracker = None


def get_daily_tracker() -> DailyTaskTracker:
    """获取全局的每日追踪器实例"""
    global _daily_tracker
    if _daily_tracker is None:
        _daily_tracker = DailyTaskTracker()
    return _daily_tracker


# 便捷函数
def record_created(count: int = 1, **kwargs):
    """记录创建的任务"""
    get_daily_tracker().record_task_created(count, **kwargs)


def record_completed(count: int = 1):
    """记录完成的任务"""
    get_daily_tracker().record_task_completed(count)


def record_failed(count: int = 1):
    """记录失败的任务"""
    get_daily_tracker().record_task_failed(count)


def get_trend_report(days: int = 7) -> str:
    """获取趋势报告"""
    return get_daily_tracker().generate_trend_report(days)