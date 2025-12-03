#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Bisect性能监控指标系统

该模块提供了完整的监控和度量功能，用于跟踪bisect系统的性能指标：
1. 结果复用率
2. 验证准确率
3. 误判率
4. 平均节省时间
5. 资源利用率
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
    """单个bisect任务的度量数据"""
    task_id: str
    error_id: str
    start_time: datetime
    end_time: Optional[datetime] = None
    status: str = "pending"  # pending, running, success, failed, reused
    reused_from: Optional[str] = None  # 如果是复用的，记录来源任务ID
    verification_attempted: bool = False
    verification_passed: bool = False
    time_saved_seconds: float = 0.0
    cpu_usage_percent: float = 0.0
    memory_usage_mb: float = 0.0
    similarity_score: float = 0.0
    error_category: str = ""


class MetricsCollector:
    """度量数据收集器"""

    def __init__(self, max_history: int = 1000):
        """
        初始化度量收集器

        Args:
            max_history: 保留的历史记录最大数量
        """
        self.metrics_history = deque(maxlen=max_history)
        self.current_tasks = {}  # 正在进行的任务
        self.lock = threading.Lock()

        # 累计统计
        self.total_tasks = 0
        self.reused_tasks = 0
        self.verified_tasks = 0
        self.verification_passed = 0
        self.verification_failed = 0

        # 时间统计
        self.total_time_saved = 0.0
        self.avg_bisect_time = 0.0

        # 资源使用统计
        self.peak_cpu_usage = 0.0
        self.peak_memory_usage = 0.0

    def start_task(self, task_id: str, error_id: str, similarity_score: float = 0.0) -> None:
        """记录任务开始"""
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
        记录任务结束

        Args:
            task_id: 任务ID
            status: 任务状态 (success, failed, reused)
            **kwargs: 其他度量数据
        """
        with self.lock:
            if task_id not in self.current_tasks:
                return

            metrics = self.current_tasks[task_id]
            metrics.end_time = datetime.now()
            metrics.status = status

            # 更新其他字段
            for key, value in kwargs.items():
                if hasattr(metrics, key):
                    setattr(metrics, key, value)

            # 计算任务执行时间
            if metrics.end_time and metrics.start_time:
                duration = (metrics.end_time - metrics.start_time).total_seconds()

                # 更新平均bisect时间
                if status == "success" and not metrics.reused_from:
                    # 只统计实际执行的bisect任务
                    if self.avg_bisect_time == 0:
                        self.avg_bisect_time = duration
                    else:
                        # 指数移动平均
                        self.avg_bisect_time = 0.9 * self.avg_bisect_time + 0.1 * duration

            # 更新统计
            if status == "reused":
                self.reused_tasks += 1
                metrics.time_saved_seconds = self.avg_bisect_time * 0.8  # 估计节省80%的时间
                self.total_time_saved += metrics.time_saved_seconds

            if metrics.verification_attempted:
                self.verified_tasks += 1
                if metrics.verification_passed:
                    self.verification_passed += 1
                else:
                    self.verification_failed += 1

            # 记录资源使用
            metrics.cpu_usage_percent = self._get_current_cpu_usage()
            metrics.memory_usage_mb = self._get_current_memory_usage()

            # 更新峰值
            self.peak_cpu_usage = max(self.peak_cpu_usage, metrics.cpu_usage_percent)
            self.peak_memory_usage = max(self.peak_memory_usage, metrics.memory_usage_mb)

            # 移到历史记录
            self.metrics_history.append(metrics)
            del self.current_tasks[task_id]

    def record_verification(self, task_id: str, passed: bool) -> None:
        """记录验证结果"""
        with self.lock:
            if task_id in self.current_tasks:
                metrics = self.current_tasks[task_id]
                metrics.verification_attempted = True
                metrics.verification_passed = passed

    def get_current_metrics(self) -> Dict[str, Any]:
        """获取当前性能指标"""
        with self.lock:
            if self.total_tasks == 0:
                return self._empty_metrics()

            # 计算近期数据（最近100个任务）
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
        """返回空的度量数据"""
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
        """计算吞吐量（每小时完成的任务数）"""
        if not recent_tasks:
            return 0.0

        # 获取时间范围
        start_time = min(t.start_time for t in recent_tasks)
        end_time = max(t.end_time or datetime.now() for t in recent_tasks)

        hours = (end_time - start_time).total_seconds() / 3600
        if hours == 0:
            return 0.0

        return len(recent_tasks) / hours

    def _calculate_trends(self, recent_tasks: List[BisectTaskMetrics]) -> Dict[str, str]:
        """计算趋势（上升、下降、稳定）"""
        if len(recent_tasks) < 10:
            return {"reuse_trend": "insufficient_data", "accuracy_trend": "insufficient_data"}

        # 分成两半比较
        mid = len(recent_tasks) // 2
        first_half = recent_tasks[:mid]
        second_half = recent_tasks[mid:]

        # 计算复用率趋势
        first_reuse = sum(1 for t in first_half if t.status == "reused") / len(first_half)
        second_reuse = sum(1 for t in second_half if t.status == "reused") / len(second_half)

        if second_reuse > first_reuse * 1.1:
            reuse_trend = "improving"
        elif second_reuse < first_reuse * 0.9:
            reuse_trend = "declining"
        else:
            reuse_trend = "stable"

        # 计算准确率趋势
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
        """生成优化建议"""
        recommendations = []

        # 基于复用率
        reuse_rate = self.reused_tasks / self.total_tasks if self.total_tasks > 0 else 0
        if reuse_rate < 0.1:
            recommendations.append("复用率较低(<10%)，建议降低相似度阈值或扩大搜索范围")
        elif reuse_rate > 0.5:
            recommendations.append("复用率很高(>50%)，系统运行良好")

        # 基于验证准确率
        if self.verified_tasks > 10:
            accuracy = self.verification_passed / self.verified_tasks
            if accuracy < 0.5:
                recommendations.append("验证准确率低(<50%)，建议提高相似度阈值")
            elif accuracy > 0.8:
                recommendations.append("验证准确率高(>80%)，相似度算法效果良好")

        # 基于误判率
        if self.verified_tasks > 0:
            false_positive = self.verification_failed / self.verified_tasks
            if false_positive > 0.3:
                recommendations.append("误判率过高(>30%)，建议优化相似度算法")

        # 基于资源使用
        if self.peak_cpu_usage > 80:
            recommendations.append("CPU使用率峰值过高(>80%)，建议优化并发数或增加资源")

        if self.peak_memory_usage > 4096:  # 4GB
            recommendations.append("内存使用峰值过高(>4GB)，建议优化缓存策略")

        if not recommendations:
            recommendations.append("系统运行正常，各项指标在合理范围内")

        return recommendations

    def _get_current_cpu_usage(self) -> float:
        """获取当前CPU使用率"""
        try:
            return psutil.cpu_percent(interval=0)  # 改为0，不等待
        except:
            return 0.0

    def _get_current_memory_usage(self) -> float:
        """获取当前内存使用量（MB）"""
        try:
            process = psutil.Process()
            return process.memory_info().rss / 1024 / 1024
        except:
            return 0.0

    def export_metrics(self, filepath: str) -> None:
        """导出度量数据到文件"""
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

            # 转换datetime对象为字符串
            def convert_datetime(obj):
                if isinstance(obj, datetime):
                    return obj.isoformat()
                return obj

            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, default=convert_datetime, ensure_ascii=False)


class MetricsReporter:
    """度量报告生成器"""

    def __init__(self, collector: MetricsCollector):
        self.collector = collector

    def generate_report(self) -> str:
        """生成文本格式的性能报告"""
        metrics = self.collector.get_current_metrics()

        report = []
        report.append("=" * 60)
        report.append("Bisect 系统性能报告")
        report.append("=" * 60)
        report.append(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")

        # 任务概况
        summary = metrics['summary']
        report.append("【任务概况】")
        report.append(f"  总任务数: {summary['total_tasks']}")
        report.append(f"  活跃任务: {summary['active_tasks']}")
        report.append(f"  完成任务: {summary['completed_tasks']}")
        report.append("")

        # 复用指标
        reuse = metrics['reuse_metrics']
        report.append("【结果复用】")
        report.append(f"  复用率: {reuse['reuse_rate']:.1%}")
        report.append(f"  复用次数: {reuse['total_reused']}")
        report.append(f"  节省时间: {reuse['time_saved_hours']:.1f} 小时")
        report.append("")

        # 验证指标
        verify = metrics['verification_metrics']
        report.append("【验证效果】")
        report.append(f"  验证率: {verify['verification_rate']:.1%}")
        report.append(f"  准确率: {verify['accuracy']:.1%}")
        report.append(f"  误判率: {verify['false_positive_rate']:.1%}")
        report.append(f"  验证统计: 成功{verify['passed']} / 失败{verify['failed']} / 总计{verify['total_verified']}")
        report.append("")

        # 性能指标
        perf = metrics['performance_metrics']
        report.append("【性能指标】")
        report.append(f"  平均bisect时间: {perf['avg_bisect_time_minutes']:.1f} 分钟")
        report.append(f"  平均节省时间: {perf['avg_time_saved_per_reuse_minutes']:.1f} 分钟/次")
        report.append(f"  吞吐量: {perf['throughput_per_hour']:.1f} 任务/小时")
        report.append("")

        # 资源使用
        resource = metrics['resource_metrics']
        report.append("【资源使用】")
        report.append(f"  当前CPU: {resource['current_cpu_percent']:.1f}%")
        report.append(f"  当前内存: {resource['current_memory_mb']:.1f} MB")
        report.append(f"  峰值CPU: {resource['peak_cpu_percent']:.1f}%")
        report.append(f"  峰值内存: {resource['peak_memory_mb']:.1f} MB")
        report.append("")

        # 趋势分析
        trends = metrics['recent_trends']
        if trends:
            report.append("【趋势分析】")
            report.append(f"  复用率趋势: {trends.get('reuse_trend', 'N/A')}")
            report.append(f"  准确率趋势: {trends.get('accuracy_trend', 'N/A')}")
            report.append("")

        # 优化建议
        report.append("【优化建议】")
        for i, recommendation in enumerate(metrics['recommendations'], 1):
            report.append(f"  {i}. {recommendation}")
        report.append("")

        report.append("=" * 60)

        return "\n".join(report)


# 全局度量收集器实例
global_metrics_collector = MetricsCollector()


def get_metrics_collector() -> MetricsCollector:
    """获取全局度量收集器"""
    return global_metrics_collector


def test_metrics_system():
    """测试度量系统"""
    collector = MetricsCollector()

    # 模拟一些任务
    print("模拟bisect任务执行...")

    # 任务1：成功的bisect
    collector.start_task("task1", "error1", similarity_score=0.0)
    time.sleep(0.1)
    collector.end_task("task1", "success")

    # 任务2：复用的任务
    collector.start_task("task2", "error2", similarity_score=0.85)
    collector.record_verification("task2", True)
    time.sleep(0.05)
    collector.end_task("task2", "reused", reused_from="task1")

    # 任务3：验证失败的任务
    collector.start_task("task3", "error3", similarity_score=0.75)
    collector.record_verification("task3", False)
    time.sleep(0.08)
    collector.end_task("task3", "success")

    # 任务4：失败的任务
    collector.start_task("task4", "error4", similarity_score=0.0)
    time.sleep(0.06)
    collector.end_task("task4", "failed")

    # 任务5：又一个复用的任务
    collector.start_task("task5", "error5", similarity_score=0.92)
    collector.record_verification("task5", True)
    time.sleep(0.04)
    collector.end_task("task5", "reused", reused_from="task2")

    # 生成报告
    reporter = MetricsReporter(collector)
    print("\n" + reporter.generate_report())

    # 导出度量数据
    export_file = "/tmp/bisect_metrics.json"
    collector.export_metrics(export_file)
    print(f"\n度量数据已导出到: {export_file}")


if __name__ == "__main__":
    test_metrics_system()