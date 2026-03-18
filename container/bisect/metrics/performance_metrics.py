#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Bisect

，bisect：
1. 
2. verify
3. 
4. 
5. 
"""

import time
import json
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field, asdict
from collections import deque, defaultdict
import threading
import psutil


@dataclass
class BisectTaskMetrics:
    """bisecttask"""
    task_id: str
    error_id: str
    start_time: datetime
    end_time: Optional[datetime] = None
    status: str = "pending"  # pending, running, success, failed, reused
    reused_from: Optional[str] = None  # ，taskID
    verification_attempted: bool = False
    verification_passed: bool = False
    time_saved_seconds: float = 0.0
    cpu_usage_percent: float = 0.0
    memory_usage_mb: float = 0.0
    similarity_score: float = 0.0
    error_category: str = ""


class MetricsCollector:
    """"""

    def __init__(self, max_history: int = 1000):
        """
        initialize

        Args:
            max_history: count
        """
        self.metrics_history = deque(maxlen=max_history)
        self.current_tasks = {}  # task
        self.lock = threading.Lock()

        # stats
        self.total_tasks = 0
        self.reused_tasks = 0
        self.verified_tasks = 0
        self.verification_passed = 0
        self.verification_failed = 0

        # stats
        self.total_time_saved = 0.0
        self.avg_bisect_time = 0.0

        # stats
        self.peak_cpu_usage = 0.0
        self.peak_memory_usage = 0.0

    def start_task(self, task_id: str, error_id: str, similarity_score: float = 0.0) -> None:
        """taskstart"""
        with self.lock:
            metrics = BisectTaskMetrics(
                task_id=task_id,
                error_id=error_id,
                start_time=datetime.now(),
                similarity_score=similarity_score
            )
            self.current_tasks[task_id] = metrics
            self.total_tasks += 1

    def end_task(self, task_id: str, status: str, **kwargs) -> None:
        """
        taskfinish

        Args:
            task_id: taskID
            status: taskstatus (success, failed, reused)
            **kwargs: 
        """
        with self.lock:
            if task_id not in self.current_tasks:
                return

            metrics = self.current_tasks[task_id]
            metrics.end_time = datetime.now()
            metrics.status = status

            # 
            for key, value in kwargs.items():
                if hasattr(metrics, key):
                    setattr(metrics, key, value)

            # task
            if metrics.end_time and metrics.start_time:
                duration = (metrics.end_time - metrics.start_time).total_seconds()

                # bisect
                if status == "success" and not metrics.reused_from:
                    # statsbisecttask
                    if self.avg_bisect_time == 0:
                        self.avg_bisect_time = duration
                    else:
                        # 
                        self.avg_bisect_time = 0.9 * self.avg_bisect_time + 0.1 * duration

            # stats
            if status == "reused":
                self.reused_tasks += 1
                metrics.time_saved_seconds = self.avg_bisect_time * 0.8  # 80%
                self.total_time_saved += metrics.time_saved_seconds

            if metrics.verification_attempted:
                self.verified_tasks += 1
                if metrics.verification_passed:
                    self.verification_passed += 1
                else:
                    self.verification_failed += 1

            # 
            metrics.cpu_usage_percent = self._get_current_cpu_usage()
            metrics.memory_usage_mb = self._get_current_memory_usage()

            # 
            self.peak_cpu_usage = max(self.peak_cpu_usage, metrics.cpu_usage_percent)
            self.peak_memory_usage = max(self.peak_memory_usage, metrics.memory_usage_mb)

            # 
            self.metrics_history.append(metrics)
            del self.current_tasks[task_id]

    def record_verification(self, task_id: str, passed: bool) -> None:
        """verify"""
        with self.lock:
            if task_id in self.current_tasks:
                metrics = self.current_tasks[task_id]
                metrics.verification_attempted = True
                metrics.verification_passed = passed

    def get_current_metrics(self) -> Dict[str, Any]:
        """get"""
        with self.lock:
            if self.total_tasks == 0:
                return self._empty_metrics()

            # （100task）
            recent_tasks = list(self.metrics_history)[-100:]

            return {
                "summary": {
                    "total_tasks": self.total_tasks,
                    "active_tasks": len(self.current_tasks),
                    "completed_tasks": len(self.metrics_history)
                },
                "reuse_metrics": {
                    "reuse_rate": self.reused_tasks / self.total_tasks if self.total_tasks > 0 else 0,
                    "total_reused": self.reused_tasks,
                    "time_saved_hours": self.total_time_saved / 3600
                },
                "verification_metrics": {
                    "verification_rate": self.verified_tasks / self.total_tasks if self.total_tasks > 0 else 0,
                    "accuracy": self.verification_passed / self.verified_tasks if self.verified_tasks > 0 else 0,
                    "false_positive_rate": self.verification_failed / self.verified_tasks if self.verified_tasks > 0 else 0,
                    "total_verified": self.verified_tasks,
                    "passed": self.verification_passed,
                    "failed": self.verification_failed
                },
                "performance_metrics": {
                    "avg_bisect_time_minutes": self.avg_bisect_time / 60,
                    "avg_time_saved_per_reuse_minutes": (self.total_time_saved / self.reused_tasks / 60) if self.reused_tasks > 0 else 0,
                    "throughput_per_hour": self._calculate_throughput(recent_tasks)
                },
                "resource_metrics": {
                    "current_cpu_percent": self._get_current_cpu_usage(),
                    "current_memory_mb": self._get_current_memory_usage(),
                    "peak_cpu_percent": self.peak_cpu_usage,
                    "peak_memory_mb": self.peak_memory_usage
                },
                "recent_trends": self._calculate_trends(recent_tasks),
                "recommendations": self._generate_recommendations()
            }

    def _empty_metrics(self) -> Dict[str, Any]:
        """"""
        return {
            "summary": {"total_tasks": 0, "active_tasks": 0, "completed_tasks": 0},
            "reuse_metrics": {"reuse_rate": 0, "total_reused": 0, "time_saved_hours": 0},
            "verification_metrics": {
                "verification_rate": 0, "accuracy": 0, "false_positive_rate": 0,
                "total_verified": 0, "passed": 0, "failed": 0
            },
            "performance_metrics": {
                "avg_bisect_time_minutes": 0,
                "avg_time_saved_per_reuse_minutes": 0,
                "throughput_per_hour": 0
            },
            "resource_metrics": {
                "current_cpu_percent": 0, "current_memory_mb": 0,
                "peak_cpu_percent": 0, "peak_memory_mb": 0
            },
            "recent_trends": {},
            "recommendations": []
        }

    def _calculate_throughput(self, recent_tasks: List[BisectTaskMetrics]) -> float:
        """（completedtask）"""
        if not recent_tasks:
            return 0.0

        # get
        start_time = min(t.start_time for t in recent_tasks)
        end_time = max(t.end_time or datetime.now() for t in recent_tasks)

        hours = (end_time - start_time).total_seconds() / 3600
        if hours == 0:
            return 0.0

        return len(recent_tasks) / hours

    def _calculate_trends(self, recent_tasks: List[BisectTaskMetrics]) -> Dict[str, str]:
        """（、、）"""
        if len(recent_tasks) < 10:
            return {"reuse_trend": "insufficient_data", "accuracy_trend": "insufficient_data"}

        # 
        mid = len(recent_tasks) // 2
        first_half = recent_tasks[:mid]
        second_half = recent_tasks[mid:]

        # 
        first_reuse = sum(1 for t in first_half if t.status == "reused") / len(first_half)
        second_reuse = sum(1 for t in second_half if t.status == "reused") / len(second_half)

        if second_reuse > first_reuse * 1.1:
            reuse_trend = "improving"
        elif second_reuse < first_reuse * 0.9:
            reuse_trend = "declining"
        else:
            reuse_trend = "stable"

        # 
        first_verified = [t for t in first_half if t.verification_attempted]
        second_verified = [t for t in second_half if t.verification_attempted]

        if first_verified and second_verified:
            first_accuracy = sum(1 for t in first_verified if t.verification_passed) / len(first_verified)
            second_accuracy = sum(1 for t in second_verified if t.verification_passed) / len(second_verified)

            if second_accuracy > first_accuracy * 1.05:
                accuracy_trend = "improving"
            elif second_accuracy < first_accuracy * 0.95:
                accuracy_trend = "declining"
            else:
                accuracy_trend = "stable"
        else:
            accuracy_trend = "insufficient_data"

        return {
            "reuse_trend": reuse_trend,
            "accuracy_trend": accuracy_trend
        }

    def _generate_recommendations(self) -> List[str]:
        """"""
        recommendations = []

        # 
        reuse_rate = self.reused_tasks / self.total_tasks if self.total_tasks > 0 else 0
        if reuse_rate < 0.1:
            recommendations.append("(<10%)，")
        elif reuse_rate > 0.5:
            recommendations.append("(>50%)，")

        # verify
        if self.verified_tasks > 10:
            accuracy = self.verification_passed / self.verified_tasks
            if accuracy < 0.5:
                recommendations.append("verify(<50%)，")
            elif accuracy > 0.8:
                recommendations.append("verify(>80%)，")

        # 
        if self.verified_tasks > 0:
            false_positive = self.verification_failed / self.verified_tasks
            if false_positive > 0.3:
                recommendations.append("(>30%)，")

        # 
        if self.peak_cpu_usage > 80:
            recommendations.append("CPU(>80%)，")

        if self.peak_memory_usage > 4096:  # 4GB
            recommendations.append("(>4GB)，")

        if not recommendations:
            recommendations.append("，")

        return recommendations

    def _get_current_cpu_usage(self) -> float:
        """getCPU"""
        try:
            return psutil.cpu_percent(interval=0)  # 0，
        except (OSError, psutil.Error):
            return 0.0

    def _get_current_memory_usage(self) -> float:
        """get（MB）"""
        try:
            process = psutil.Process()
            return process.memory_info().rss / 1024 / 1024
        except (OSError, psutil.Error):
            return 0.0

    def export_metrics(self, filepath: str) -> None:
        """file"""
        with self.lock:
            data = {
                "export_time": datetime.now().isoformat(),
                "current_metrics": self.get_current_metrics(),
                "history": [asdict(m) for m in list(self.metrics_history)[-100:]],
                "detailed_stats": {
                    "total_tasks": self.total_tasks,
                    "reused_tasks": self.reused_tasks,
                    "verified_tasks": self.verified_tasks,
                    "verification_passed": self.verification_passed,
                    "verification_failed": self.verification_failed,
                    "total_time_saved_hours": self.total_time_saved / 3600,
                    "avg_bisect_time_minutes": self.avg_bisect_time / 60
                }
            }

            # datetime
            def convert_datetime(obj):
                if isinstance(obj, datetime):
                    return obj.isoformat()
                return obj

            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, default=convert_datetime, ensure_ascii=False)


class MetricsReporter:
    """"""

    def __init__(self, collector: MetricsCollector):
        self.collector = collector

    def generate_report(self) -> str:
        """"""
        metrics = self.collector.get_current_metrics()

        report = []
        report.append("=" * 60)
        report.append("Bisect ")
        report.append("=" * 60)
        report.append(f": {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")

        # task
        summary = metrics['summary']
        report.append("【task】")
        report.append(f"  task: {summary['total_tasks']}")
        report.append(f"  task: {summary['active_tasks']}")
        report.append(f"  completedtask: {summary['completed_tasks']}")
        report.append("")

        # 
        reuse = metrics['reuse_metrics']
        report.append("【】")
        report.append(f"  : {reuse['reuse_rate']:.1%}")
        report.append(f"  : {reuse['total_reused']}")
        report.append(f"  : {reuse['time_saved_hours']:.1f} ")
        report.append("")

        # verify
        verify = metrics['verification_metrics']
        report.append("【verify】")
        report.append(f"  verify: {verify['verification_rate']:.1%}")
        report.append(f"  : {verify['accuracy']:.1%}")
        report.append(f"  : {verify['false_positive_rate']:.1%}")
        report.append(f"  verifystats: success{verify['passed']} / failed{verify['failed']} / {verify['total_verified']}")
        report.append("")

        # 
        perf = metrics['performance_metrics']
        report.append("【】")
        report.append(f"  bisect: {perf['avg_bisect_time_minutes']:.1f} ")
        report.append(f"  : {perf['avg_time_saved_per_reuse_minutes']:.1f} /")
        report.append(f"  : {perf['throughput_per_hour']:.1f} task/")
        report.append("")

        # 
        resource = metrics['resource_metrics']
        report.append("【】")
        report.append(f"  CPU: {resource['current_cpu_percent']:.1f}%")
        report.append(f"  : {resource['current_memory_mb']:.1f} MB")
        report.append(f"  CPU: {resource['peak_cpu_percent']:.1f}%")
        report.append(f"  : {resource['peak_memory_mb']:.1f} MB")
        report.append("")

        # 
        trends = metrics['recent_trends']
        if trends:
            report.append("【】")
            report.append(f"  : {trends.get('reuse_trend', 'N/A')}")
            report.append(f"  : {trends.get('accuracy_trend', 'N/A')}")
            report.append("")

        # 
        report.append("【】")
        for i, recommendation in enumerate(metrics['recommendations'], 1):
            report.append(f"  {i}. {recommendation}")
        report.append("")

        report.append("=" * 60)

        return "\n".join(report)


# instance
global_metrics_collector = MetricsCollector()


def get_metrics_collector() -> MetricsCollector:
    """get"""
    return global_metrics_collector


def test_metrics_system():
    """test"""
    collector = MetricsCollector()

    # task
    print("bisecttask...")

    # task1：successbisect
    collector.start_task("task1", "error1", similarity_score=0.0)
    time.sleep(0.1)
    collector.end_task("task1", "success")

    # task2：task
    collector.start_task("task2", "error2", similarity_score=0.85)
    collector.record_verification("task2", True)
    time.sleep(0.05)
    collector.end_task("task2", "reused", reused_from="task1")

    # task3：verifyfailedtask
    collector.start_task("task3", "error3", similarity_score=0.75)
    collector.record_verification("task3", False)
    time.sleep(0.08)
    collector.end_task("task3", "success")

    # task4：failedtask
    collector.start_task("task4", "error4", similarity_score=0.0)
    time.sleep(0.06)
    collector.end_task("task4", "failed")

    # task5：task
    collector.start_task("task5", "error5", similarity_score=0.92)
    collector.record_verification("task5", True)
    time.sleep(0.04)
    collector.end_task("task5", "reused", reused_from="task2")

    # 
    reporter = MetricsReporter(collector)
    print("\n" + reporter.generate_report())

    # 
    export_file = "/tmp/bisect_metrics.json"
    collector.export_metrics(export_file)
    print(f"\n: {export_file}")


if __name__ == "__main__":
    test_metrics_system()