#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
taskstats

createcompletedbisecttaskcount，。
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
    taskcreatecompleted
    """

    def __init__(self, stats_dir: str = "/result/bisect/daily_stats"):
        """
        initializestats

        Args:
            stats_dir: stats
        """
        self.stats_dir = Path(stats_dir)
        self.stats_dir.mkdir(parents=True, exist_ok=True)

        # statsfile
        today = datetime.now().strftime("%Y-%m-%d")
        self.today_file = self.stats_dir / f"{today}.json"

        # initializestats
        self.today_stats = self._load_today_stats()

    def _load_today_stats(self) -> Dict:
        """stats"""
        if self.today_file.exists():
            try:
                with open(self.today_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"statsfilefailed: {e}")

        # initializestats
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
        createtask

        Args:
            count: createtask
            category: task
            repo: repo
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
        """completedtask"""
        hour = datetime.now().strftime("%H")

        self.today_stats['completed'] += count
        self.today_stats['hourly_completed'][hour] = \
            self.today_stats['hourly_completed'].get(hour, 0) + count

        self._save_stats()

    def record_task_failed(self, count: int = 1):
        """failedtask"""
        self.today_stats['failed'] += count
        self._save_stats()

    def update_in_progress(self, count: int):
        """task"""
        self.today_stats['in_progress'] = count
        self._save_stats()

    def _save_stats(self):
        """statsfile"""
        self.today_stats['last_update'] = datetime.now().isoformat()

        try:
            with open(self.today_file, 'w') as f:
                json.dump(self.today_stats, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logger.error(f"statsfilefailed: {e}")

    def get_daily_summary(self, days: int = 7) -> List[Dict]:
        """
        getstats

        Args:
            days: stats

        Returns:
            statslist
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
                    logger.error(f" {date_str} statsfailed: {e}")

        return sorted(summaries, key=lambda x: x['date'], reverse=True)

    def generate_trend_report(self, days: int = 7) -> str:
        """
        

        Args:
            days: stats

        Returns:
            
        """
        summaries = self.get_daily_summary(days)

        if not summaries:
            return "stats"

        report = []
        report.append("=" * 80)
        report.append(f"Bisect task（ {days} ）")
        report.append("=" * 80)
        report.append("")

        # stats
        total_created = sum(s.get('created', 0) for s in summaries)
        total_completed = sum(s.get('completed', 0) for s in summaries)
        total_failed = sum(s.get('failed', 0) for s in summaries)

        report.append("【stats】")
        report.append(f"  createtask: {total_created}")
        report.append(f"  completedtask: {total_completed}")
        report.append(f"  failedtask: {total_failed}")
        report.append(f"  completed: {total_completed/total_created*100:.1f}%" if total_created > 0 else "  completed: N/A")
        report.append("")

        # 
        report.append("【】")
        report.append("       | create | completed | failed |  | completed")
        report.append("-" * 60)

        for summary in summaries:
            date = summary['date']
            created = summary.get('created', 0)
            completed = summary.get('completed', 0)
            failed = summary.get('failed', 0)
            in_progress = summary.get('in_progress', 0)
            completion_rate = f"{completed/created*100:.1f}%" if created > 0 else "N/A"

            report.append(f"{date} | {created:4} | {completed:4} | {failed:4} | {in_progress:6} | {completion_rate:>7}")

        # 
        if len(summaries) >= 2:
            report.append("")
            report.append("【】")

            # 
            avg_created = total_created / len(summaries)
            avg_completed = total_completed / len(summaries)

            report.append(f"  create: {avg_created:.1f} task")
            report.append(f"  completed: {avg_completed:.1f} task")

            # （）
            if summaries[0]['created'] > 0 and summaries[1]['created'] > 0:
                growth = (summaries[0]['created'] - summaries[1]['created']) / summaries[1]['created'] * 100
                report.append(f"  create: {growth:+.1f}%")

        # repo（）
        if summaries and 'repositories' in summaries[0] and summaries[0]['repositories']:
            report.append("")
            report.append("【repo】")
            repos = sorted(summaries[0]['repositories'].items(), key=lambda x: x[1], reverse=True)[:5]
            for repo, count in repos:
                report.append(f"  - {repo}: {count} task")

        report.append("")
        report.append("=" * 80)

        return "\n".join(report)

    def get_current_stats(self) -> Dict:
        """getstats"""
        return self.today_stats.copy()


# instance
_daily_tracker = None


def get_daily_tracker() -> DailyTaskTracker:
    """getinstance"""
    global _daily_tracker
    if _daily_tracker is None:
        _daily_tracker = DailyTaskTracker()
    return _daily_tracker


# 
def record_created(count: int = 1, **kwargs):
    """createtask"""
    get_daily_tracker().record_task_created(count, **kwargs)


def record_completed(count: int = 1):
    """completedtask"""
    get_daily_tracker().record_task_completed(count)


def record_failed(count: int = 1):
    """failedtask"""
    get_daily_tracker().record_task_failed(count)


def get_trend_report(days: int = 7) -> str:
    """get"""
    return get_daily_tracker().generate_trend_report(days)