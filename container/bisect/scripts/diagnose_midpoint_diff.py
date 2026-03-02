#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Diagnostic script: compare sample differences between Producer and py_bisect queries

Usage:
    python diagnose_midpoint_diff.py --task-id <bisect_task_id>
    python diagnose_midpoint_diff.py --commit <commit> --suite <suite> --metric <metric>
"""

import os
import sys
import json
import argparse
from typing import Dict, List, Optional, Tuple
from collections import defaultdict

# Add path
sys.path.insert(0, os.path.join(os.environ.get('LKP_SRC', '/srv/cci'), 'programs/bisect-py/'))

from lkp_bisect.db.manticore import ManticoreClient


class MidpointDiagnoser:
    """Diagnose midpoint differences"""

    def __init__(self):
        self.client = ManticoreClient()

    def get_task_info(self, task_id: int) -> Optional[Dict]:
        """Get bisect task info"""
        sql = f"SELECT * FROM bisect WHERE id = {task_id}"
        result = self.client.sql_select(sql)
        if result:
            return result[0]
        return None

    def query_all_jobs_for_commit(self, commit: str, suite: str,
                                   testbox: str = None,
                                   metric: str = None,
                                   hours: int = None) -> List[Dict]:
        """Query all test jobs for a commit

        Args:
            hours: time range (hours), None means no limit
        """
        import time as time_module

        # Build query
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
                except json.JSONDecodeError:
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

            # If metric is specified, only keep jobs with that metric
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
        """Compare Producer-recorded samples with all available samples in database"""

        result = {
            'task_info': None,
            'producer_samples': {'v1': [], 'v2': []},
            'all_db_samples': {'v1': [], 'v2': []},
            'analysis': {}
        }

        # If task_id is provided, get parameters from the task
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
                except json.JSONDecodeError:
                    j = {}

            baseline_commit = j.get('baseline_commit') or j.get('good_commit')
            current_commit = j.get('current_commit') or j.get('bad_commit')
            suite = j.get('suite')
            metric = task.get('bisect_metric')
            # Get testbox from task (new field)
            if not testbox:
                testbox = j.get('testbox')

            # Producer-recorded samples
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
        print(f"Diagnostic parameters:")
        print(f"  baseline_commit: {baseline_commit}")
        print(f"  current_commit: {current_commit}")
        print(f"  suite: {suite}")
        print(f"  metric: {metric}")
        print(f"  testbox: {testbox or '(all)'}")
        print(f"  hours: {hours or '(unlimited)'}")
        if not testbox and task_id:
            print(f"  Warning: task has no testbox field (old task), query results may include data from multiple testboxes")
        if not hours:
            print(f"  Warning: no time range specified, querying all historical data (Producer uses 168 hours by default)")
        print(f"{'='*60}\n")

        # Query all samples from database
        v1_jobs = self.query_all_jobs_for_commit(baseline_commit, suite, testbox, metric, hours)
        v2_jobs = self.query_all_jobs_for_commit(current_commit, suite, testbox, metric, hours)

        result['all_db_samples']['v1'] = [j['metric_value'] for j in v1_jobs if 'metric_value' in j]
        result['all_db_samples']['v2'] = [j['metric_value'] for j in v2_jobs if 'metric_value' in j]
        result['v1_jobs'] = v1_jobs
        result['v2_jobs'] = v2_jobs

        # Analyze
        self._analyze(result)

        return result

    def _analyze(self, result: Dict):
        """Analyze sample differences"""

        producer_v1 = result['producer_samples']['v1']
        producer_v2 = result['producer_samples']['v2']
        all_v1 = result['all_db_samples']['v1']
        all_v2 = result['all_db_samples']['v2']

        analysis = result['analysis']

        # Sample count comparison
        analysis['sample_counts'] = {
            'producer_v1': len(producer_v1),
            'producer_v2': len(producer_v2),
            'all_db_v1': len(all_v1),
            'all_db_v2': len(all_v2)
        }

        # Range calculation
        if all_v1:
            analysis['all_v1_range'] = (min(all_v1), max(all_v1))
            analysis['all_v1_avg'] = sum(all_v1) / len(all_v1)

        if all_v2:
            analysis['all_v2_range'] = (min(all_v2), max(all_v2))
            analysis['all_v2_avg'] = sum(all_v2) / len(all_v2)

        # Check overlap
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
                # Calculate overlap range
                overlap_start = max(v1_min, v2_min)
                overlap_end = min(v1_max, v2_max)
                analysis['overlap_range'] = (overlap_start, overlap_end)

        # Check if Producer samples are a subset of all samples
        if producer_v1 and all_v1:
            analysis['producer_v1_is_subset'] = set(producer_v1).issubset(set(all_v1))
            analysis['producer_v1_missing'] = list(set(all_v1) - set(producer_v1))

        if producer_v2 and all_v2:
            analysis['producer_v2_is_subset'] = set(producer_v2).issubset(set(all_v2))
            analysis['producer_v2_missing'] = list(set(all_v2) - set(producer_v2))

    def print_report(self, result: Dict):
        """Print diagnostic report"""

        analysis = result.get('analysis', {})

        print("\n" + "="*60)
        print("诊断报告")
        print("="*60)

        # Sample counts
        counts = analysis.get('sample_counts', {})
        print(f"\n[Sample Counts]")
        print(f"  Producer v1 (baseline): {counts.get('producer_v1', 0)}")
        print(f"  Producer v2 (current):  {counts.get('producer_v2', 0)}")
        print(f"  Database v1 (all):      {counts.get('all_db_v1', 0)}")
        print(f"  Database v2 (all):      {counts.get('all_db_v2', 0)}")

        # Producer samples
        print(f"\n[Producer Recorded Samples]")
        print(f"  v1_samples: {result['producer_samples']['v1']}")
        print(f"  v2_samples: {result['producer_samples']['v2']}")
        if 'producer_mid_point' in result:
            print(f"  mid_point:  {result.get('producer_mid_point')}")
            print(f"  v1_range:   {result.get('producer_v1_range')}")
            print(f"  v2_range:   {result.get('producer_v2_range')}")

        # All database samples
        print(f"\n[All Database Samples]")
        print(f"  v1_samples: {result['all_db_samples']['v1']}")
        print(f"  v2_samples: {result['all_db_samples']['v2']}")

        if 'all_v1_range' in analysis:
            print(f"  v1_range:   {analysis['all_v1_range']}")
            print(f"  v1_avg:     {analysis.get('all_v1_avg', 0):.2f}")

        if 'all_v2_range' in analysis:
            print(f"  v2_range:   {analysis['all_v2_range']}")
            print(f"  v2_avg:     {analysis.get('all_v2_avg', 0):.2f}")

        # Midpoint analysis
        print(f"\n[Midpoint Analysis]")
        has_gap = analysis.get('has_clear_gap')
        if has_gap is True:
            print(f"  OK: clear gap exists, bisect is feasible")
            print(f"  Computed mid_point: {analysis.get('computed_mid_point', 'N/A')}")
        elif has_gap is False:
            print(f"  FAIL: ranges overlap, midpoint condition not met")
            print(f"  Overlap range: {analysis.get('overlap_range', 'N/A')}")
        else:
            print(f"  Cannot determine (insufficient samples)")

        # Difference analysis
        print(f"\n[Difference Analysis]")
        if analysis.get('producer_v1_missing'):
            print(f"  v1 missing samples: {analysis['producer_v1_missing']}")
        if analysis.get('producer_v2_missing'):
            print(f"  v2 missing samples: {analysis['producer_v2_missing']}")

        # Job details
        print(f"\n[v1 (baseline) Jobs Details]")
        for job in result.get('v1_jobs', [])[:10]:
            print(f"  job_id: {job['job_id']}, testbox: {job['testbox']}, value: {job.get('metric_value', 'N/A')}")

        print(f"\n[v2 (current) Jobs Details]")
        for job in result.get('v2_jobs', [])[:10]:
            print(f"  job_id: {job['job_id']}, testbox: {job['testbox']}, value: {job.get('metric_value', 'N/A')}")

        print("\n" + "="*60)


def main():
    parser = argparse.ArgumentParser(description='Diagnose sample differences between Producer and py_bisect')
    parser.add_argument('--task-id', type=int, help='Bisect task ID')
    parser.add_argument('--baseline-commit', help='Baseline commit')
    parser.add_argument('--current-commit', help='Current commit')
    parser.add_argument('--suite', help='Test suite')
    parser.add_argument('--testbox', help='Testbox (optional)')
    parser.add_argument('--metric', help='Performance metric')
    parser.add_argument('--hours', type=int, help='Time range (hours), Producer default: 168')
    parser.add_argument('--json', action='store_true', help='Output in JSON format')

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
        print("\nRequired: --task-id or (--baseline-commit, --current-commit, --suite, --metric)")
        sys.exit(1)

    if args.json:
        # Handle non-serializable objects for JSON output
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
