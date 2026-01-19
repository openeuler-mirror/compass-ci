#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
诊断脚本：对比 Producer 和 py_bisect 查询到的样本差异

用法:
    python diagnose_midpoint_diff.py --task-id <bisect_task_id>
    python diagnose_midpoint_diff.py --commit <commit> --suite <suite> --metric <metric>
"""

import os
import sys
import json
import argparse
from typing import Dict, List, Optional, Tuple
from collections import defaultdict

# 添加路径
sys.path.insert(0, os.path.join(os.environ.get('LKP_SRC', '/srv/cci'), 'programs/bisect-py/'))

from manticore_simple import ManticoreClient


class MidpointDiagnoser:
    """诊断 midpoint 差异"""

    def __init__(self):
        self.client = ManticoreClient()

    def get_task_info(self, task_id: int) -> Optional[Dict]:
        """获取 bisect 任务信息"""
        sql = f"SELECT * FROM bisect WHERE id = {task_id}"
        result = self.client.sql_select(sql)
        if result:
            return result[0]
        return None

    def query_all_jobs_for_commit(self, commit: str, suite: str,
                                   testbox: str = None,
                                   metric: str = None,
                                   hours: int = None) -> List[Dict]:
        """查询某个 commit 的所有测试 jobs

        Args:
            hours: 时间范围（小时），None 表示不限制
        """
        import time as time_module

        # 构建查询
        conditions = [
            f"j.ss.linux.commit = '{commit}'",
            f"suite = '{suite}'",
            "j.job_stage = 'finish'",
            "j.job_health = 'success'",
            "j.job_data_readiness = 'complete'"
        ]

        if testbox:
            conditions.append(f"testbox = '{testbox}'")

        if hours:
            time_threshold = int(time_module.time() - hours * 3600)
            conditions.append(f"submit_time >= {time_threshold}")

        sql = f"""
            SELECT id, suite, testbox, submit_time, j
            FROM jobs
            WHERE {' AND '.join(conditions)}
            ORDER BY submit_time DESC
            LIMIT 100
        """

        result = self.client.sql_select(sql)

        jobs = []
        for item in result or []:
            j = item.get('j', {})
            if isinstance(j, str):
                try:
                    j = json.loads(j)
                except:
                    j = {}

            stats = j.get('stats', {})
            job_info = {
                'job_id': item.get('id'),
                'suite': item.get('suite'),
                'testbox': item.get('testbox'),
                'submit_time': item.get('submit_time'),
                'commit': commit,
                'stats': stats
            }

            # 如果指定了 metric，只保留有该 metric 的 jobs
            if metric:
                if metric in stats:
                    job_info['metric_value'] = stats.get(metric)
                    jobs.append(job_info)
            else:
                jobs.append(job_info)

        return jobs

    def compare_samples(self, task_id: int = None,
                        baseline_commit: str = None,
                        current_commit: str = None,
                        suite: str = None,
                        testbox: str = None,
                        metric: str = None,
                        hours: int = None) -> Dict:
        """对比 Producer 记录的样本和数据库中所有可用样本"""

        result = {
            'task_info': None,
            'producer_samples': {'v1': [], 'v2': []},
            'all_db_samples': {'v1': [], 'v2': []},
            'analysis': {}
        }

        # 如果提供了 task_id，从任务中获取参数
        if task_id:
            task = self.get_task_info(task_id)
            if not task:
                print(f"Error: Task {task_id} not found")
                return result

            result['task_info'] = task

            j = task.get('j', {})
            if isinstance(j, str):
                try:
                    j = json.loads(j)
                except:
                    j = {}

            baseline_commit = j.get('baseline_commit') or j.get('good_commit')
            current_commit = j.get('current_commit') or j.get('bad_commit')
            suite = j.get('suite')
            metric = task.get('bisect_metric')
            # 从任务中获取 testbox（新增字段）
            if not testbox:
                testbox = j.get('testbox')

            # Producer 记录的样本
            result['producer_samples']['v1'] = j.get('v1_samples', [])
            result['producer_samples']['v2'] = j.get('v2_samples', [])
            result['producer_mid_point'] = j.get('mid_point')
            result['producer_v1_range'] = j.get('v1_range')
            result['producer_v2_range'] = j.get('v2_range')

        if not all([baseline_commit, current_commit, suite, metric]):
            print("Error: Missing required parameters")
            print(f"  baseline_commit: {baseline_commit}")
            print(f"  current_commit: {current_commit}")
            print(f"  suite: {suite}")
            print(f"  metric: {metric}")
            return result

        print(f"\n{'='*60}")
        print(f"诊断参数:")
        print(f"  baseline_commit: {baseline_commit}")
        print(f"  current_commit: {current_commit}")
        print(f"  suite: {suite}")
        print(f"  metric: {metric}")
        print(f"  testbox: {testbox or '(all)'}")
        print(f"  hours: {hours or '(无限制)'}")
        if not testbox and task_id:
            print(f"  ⚠️  警告: 任务中没有 testbox 字段（旧任务），查询结果可能包含多个测试机的数据")
        if not hours:
            print(f"  ⚠️  警告: 未指定时间范围，查询所有历史数据（Producer 默认用 168 小时）")
        print(f"{'='*60}\n")

        # 查询数据库中所有样本
        v1_jobs = self.query_all_jobs_for_commit(baseline_commit, suite, testbox, metric, hours)
        v2_jobs = self.query_all_jobs_for_commit(current_commit, suite, testbox, metric, hours)

        result['all_db_samples']['v1'] = [j['metric_value'] for j in v1_jobs if 'metric_value' in j]
        result['all_db_samples']['v2'] = [j['metric_value'] for j in v2_jobs if 'metric_value' in j]
        result['v1_jobs'] = v1_jobs
        result['v2_jobs'] = v2_jobs

        # 分析
        self._analyze(result)

        return result

    def _analyze(self, result: Dict):
        """分析样本差异"""

        producer_v1 = result['producer_samples']['v1']
        producer_v2 = result['producer_samples']['v2']
        all_v1 = result['all_db_samples']['v1']
        all_v2 = result['all_db_samples']['v2']

        analysis = result['analysis']

        # 样本数量对比
        analysis['sample_counts'] = {
            'producer_v1': len(producer_v1),
            'producer_v2': len(producer_v2),
            'all_db_v1': len(all_v1),
            'all_db_v2': len(all_v2)
        }

        # 范围计算
        if all_v1:
            analysis['all_v1_range'] = (min(all_v1), max(all_v1))
            analysis['all_v1_avg'] = sum(all_v1) / len(all_v1)

        if all_v2:
            analysis['all_v2_range'] = (min(all_v2), max(all_v2))
            analysis['all_v2_avg'] = sum(all_v2) / len(all_v2)

        # 检查重叠
        if all_v1 and all_v2:
            v1_min, v1_max = min(all_v1), max(all_v1)
            v2_min, v2_max = min(all_v2), max(all_v2)

            has_gap = (v1_max < v2_min) or (v2_max < v1_min)
            analysis['has_clear_gap'] = has_gap

            if has_gap:
                if v1_max < v2_min:
                    analysis['computed_mid_point'] = (v1_max + v2_min) / 2
                else:
                    analysis['computed_mid_point'] = (v2_max + v1_min) / 2
            else:
                # 计算重叠区间
                overlap_start = max(v1_min, v2_min)
                overlap_end = min(v1_max, v2_max)
                analysis['overlap_range'] = (overlap_start, overlap_end)

        # 检查 Producer 样本是否是全量的子集
        if producer_v1 and all_v1:
            analysis['producer_v1_is_subset'] = set(producer_v1).issubset(set(all_v1))
            analysis['producer_v1_missing'] = list(set(all_v1) - set(producer_v1))

        if producer_v2 and all_v2:
            analysis['producer_v2_is_subset'] = set(producer_v2).issubset(set(all_v2))
            analysis['producer_v2_missing'] = list(set(all_v2) - set(producer_v2))

    def print_report(self, result: Dict):
        """打印诊断报告"""

        analysis = result.get('analysis', {})

        print("\n" + "="*60)
        print("诊断报告")
        print("="*60)

        # 样本数量
        counts = analysis.get('sample_counts', {})
        print(f"\n【样本数量】")
        print(f"  Producer v1 (baseline): {counts.get('producer_v1', 0)}")
        print(f"  Producer v2 (current):  {counts.get('producer_v2', 0)}")
        print(f"  数据库 v1 (all):        {counts.get('all_db_v1', 0)}")
        print(f"  数据库 v2 (all):        {counts.get('all_db_v2', 0)}")

        # Producer 样本
        print(f"\n【Producer 记录的样本】")
        print(f"  v1_samples: {result['producer_samples']['v1']}")
        print(f"  v2_samples: {result['producer_samples']['v2']}")
        if 'producer_mid_point' in result:
            print(f"  mid_point:  {result.get('producer_mid_point')}")
            print(f"  v1_range:   {result.get('producer_v1_range')}")
            print(f"  v2_range:   {result.get('producer_v2_range')}")

        # 数据库全量样本
        print(f"\n【数据库中所有样本】")
        print(f"  v1_samples: {result['all_db_samples']['v1']}")
        print(f"  v2_samples: {result['all_db_samples']['v2']}")

        if 'all_v1_range' in analysis:
            print(f"  v1_range:   {analysis['all_v1_range']}")
            print(f"  v1_avg:     {analysis.get('all_v1_avg', 0):.2f}")

        if 'all_v2_range' in analysis:
            print(f"  v2_range:   {analysis['all_v2_range']}")
            print(f"  v2_avg:     {analysis.get('all_v2_avg', 0):.2f}")

        # Midpoint 判断
        print(f"\n【Midpoint 分析】")
        has_gap = analysis.get('has_clear_gap')
        if has_gap is True:
            print(f"  ✓ 存在清晰间隙，可以 bisect")
            print(f"  计算的 mid_point: {analysis.get('computed_mid_point', 'N/A')}")
        elif has_gap is False:
            print(f"  ✗ 范围重叠，不满足 midpoint 条件")
            print(f"  重叠区间: {analysis.get('overlap_range', 'N/A')}")
        else:
            print(f"  无法判断（样本不足）")

        # 差异分析
        print(f"\n【差异分析】")
        if analysis.get('producer_v1_missing'):
            print(f"  v1 缺失的样本: {analysis['producer_v1_missing']}")
        if analysis.get('producer_v2_missing'):
            print(f"  v2 缺失的样本: {analysis['producer_v2_missing']}")

        # Job 详情
        print(f"\n【v1 (baseline) Jobs 详情】")
        for job in result.get('v1_jobs', [])[:10]:
            print(f"  job_id: {job['job_id']}, testbox: {job['testbox']}, value: {job.get('metric_value', 'N/A')}")

        print(f"\n【v2 (current) Jobs 详情】")
        for job in result.get('v2_jobs', [])[:10]:
            print(f"  job_id: {job['job_id']}, testbox: {job['testbox']}, value: {job.get('metric_value', 'N/A')}")

        print("\n" + "="*60)


def main():
    parser = argparse.ArgumentParser(description='诊断 Producer 和 py_bisect 的样本差异')
    parser.add_argument('--task-id', type=int, help='Bisect 任务 ID')
    parser.add_argument('--baseline-commit', help='Baseline commit')
    parser.add_argument('--current-commit', help='Current commit')
    parser.add_argument('--suite', help='测试套件')
    parser.add_argument('--testbox', help='测试机（可选）')
    parser.add_argument('--metric', help='性能指标')
    parser.add_argument('--hours', type=int, help='时间范围（小时），Producer 默认 168')
    parser.add_argument('--json', action='store_true', help='输出 JSON 格式')

    args = parser.parse_args()

    diagnoser = MidpointDiagnoser()

    if args.task_id:
        result = diagnoser.compare_samples(task_id=args.task_id, testbox=args.testbox, hours=args.hours)
    elif args.baseline_commit and args.current_commit and args.suite and args.metric:
        result = diagnoser.compare_samples(
            baseline_commit=args.baseline_commit,
            current_commit=args.current_commit,
            suite=args.suite,
            testbox=args.testbox,
            metric=args.metric,
            hours=args.hours
        )
    else:
        parser.print_help()
        print("\n需要提供 --task-id 或者 (--baseline-commit, --current-commit, --suite, --metric)")
        sys.exit(1)

    if args.json:
        # JSON 输出时需要处理不可序列化的对象
        output = {
            'producer_samples': result['producer_samples'],
            'all_db_samples': result['all_db_samples'],
            'analysis': result['analysis']
        }
        print(json.dumps(output, indent=2, ensure_ascii=False))
    else:
        diagnoser.print_report(result)


if __name__ == '__main__':
    main()
