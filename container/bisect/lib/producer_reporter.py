#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Producer Statistics Report Generator

Generate clear, step-by-step reports from producer run results.
"""

import os
import json
import time
from datetime import datetime
from pathlib import Path
from typing import Dict
from log_config import logger


class ProducerReporter:
    """Producer report generator"""

    def __init__(self, stats_dir: str = None):
        """
        Initialize report generator

        Args:
            stats_dir: statistics directory path, defaults to /result/bisect/producer_stats
        """
        if stats_dir is None:
            result_dir = os.environ.get('RESULT_DIR', '/result/bisect')
            stats_dir = os.path.join(result_dir, 'producer_stats')

        self.stats_base_dir = stats_dir
        os.makedirs(stats_dir, exist_ok=True)

    def generate_report(self, stats: Dict, duration: float) -> str:
        """
        Generate a clear step-by-step statistics report

        Args:
            stats: statistics data dictionary
            duration: execution duration (seconds)

        Returns:
            report content string
        """
        lines = []
        lines.append("=" * 100)
        lines.append("                          BISECT TASK PRODUCER RUN REPORT")
        lines.append("=" * 100)
        lines.append("")

        # Basic info
        cycle_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stats.get('cycle_start_time', time.time())))
        lines.append(f"Run time: {cycle_time}")
        lines.append(f"Duration: {duration:.2f} seconds")
        lines.append(f"Time range: last {stats.get('time_range_hours', 48)} hours")
        lines.append("")
        lines.append("=" * 100)
        lines.append("")

        # Phase 1: Candidate task collection and intelligent filtering
        lines.append("Phase 1: Candidate Task Collection & Intelligent Filtering")
        lines.append("-" * 100)
        lines.append(f"  Query time range: {stats.get('query_time_from', 'N/A')} -> {stats.get('query_time_to', 'N/A')}")
        lines.append(f"  Queried jobs: {stats.get('jobs_queried', 0)}")
        lines.append(f"  Cache hits (already processed): {stats.get('jobs_cache_hit', 0)}")
        lines.append(f"  Jobs to process: {stats.get('jobs_processed', 0)}")
        lines.append("")

        # Intelligent filtering results
        lines.append("  Intelligent filtering results:")
        lines.append("  -" * 50)

        # Build task filtering stats
        build_filtered = stats.get('build_tasks_filtered', 0)
        if build_filtered > 0:
            lines.append(f"  Pre-filter:")
            lines.append(f"    - Non-kernel repo package build tasks (makepkg): {build_filtered}")
            lines.append("")

        total_before = stats.get('total_errids_before_filter', 0)
        total_after = stats.get('total_errids_after_smart_filter', 0)
        filtered_count = total_before - total_after

        lines.append(f"  Total errors before filtering: {total_before}")
        lines.append(f"  Retained after smart filtering: {total_after}")
        lines.append(f"  Noise filtered out: {filtered_count}")

        if total_before > 0:
            filter_rate = (filtered_count / total_before) * 100
            lines.append(f"  Filter efficiency: {filter_rate:.1f}% (retained {total_after}/{total_before} high-quality errors)")
        lines.append("")

        # Phase 1.1: Filtering method stats
        lines.append("  Filtering method distribution:")
        smart_count = stats.get('filter_method_smart', 0)
        none_count = stats.get('filter_method_none', 0)
        lines.append(f"    - Smart filtering succeeded: {smart_count} jobs")
        lines.append(f"    - Fully filtered (no high-quality errors): {none_count} jobs")
        lines.append("")

        # Phase 2: Batch deduplication check
        lines.append("Phase 2: Batch Deduplication Check")
        lines.append("-" * 100)
        db_duplicate = stats.get('tasks_db_duplicate', 0)
        no_git_url = stats.get('tasks_no_git_url', 0)
        old_commits = stats.get('tasks_filtered_old_commits', 0)
        created_success = stats.get('tasks_created_success', 0)
        created_failed = stats.get('tasks_created_failed', 0)
        total_candidates = db_duplicate + no_git_url + old_commits + created_success + created_failed

        lines.append(f"  Dedup check candidates: {total_candidates}")
        lines.append(f"  Already in database (skipped): {db_duplicate}")
        lines.append(f"  Missing git_url (skipped): {no_git_url}")

        # Commit filtering detailed stats
        commit_checked = stats.get('tasks_commit_age_checked', 0)
        commit_not_found = stats.get('tasks_commit_hash_not_found', 0)
        total_commit_filtered = old_commits + commit_not_found
        if old_commits > 0 or commit_checked > 0 or commit_not_found > 0:
            max_age = stats.get('max_commit_age_days', 365)
            lines.append(f"  Commit filtering (total filtered: {total_commit_filtered}):")
            lines.append(f"    - Age checked: {commit_checked}")
            lines.append(f"    - No commit hash (filtered): {commit_not_found}")
            lines.append(f"    - Too old (filtered): {old_commits} (over {max_age} days)")
            if commit_checked > 0:
                filter_rate = (old_commits / commit_checked) * 100
                lines.append(f"    - Age filter rate: {filter_rate:.1f}% ({old_commits}/{commit_checked})")


        if total_candidates > 0:
            dedup_rate = (db_duplicate / total_candidates) * 100
            lines.append(f"  Dedup rate: {dedup_rate:.1f}%")
        lines.append("")

        # Phase 3: Batch task creation
        lines.append("Phase 3: Batch Task Creation")
        lines.append("-" * 100)
        lines.append(f"  Created successfully: {created_success}")
        lines.append(f"  Creation failed: {created_failed}")

        # Batch insert stats
        batch_stats = stats.get('batch_insert_stats', {})
        if batch_stats:
            lines.append(f"  Batch insert batches: {batch_stats.get('batch_count', 0)}")
            lines.append(f"  Batch insert success rate: {batch_stats.get('success_rate', 0):.1f}%")
        lines.append("")

        # Final results
        lines.append("=" * 100)
        lines.append("                                   FINAL RESULTS")
        lines.append("=" * 100)

        processed = stats.get('jobs_processed', 0)
        success_rate = (created_success / processed * 100) if processed > 0 else 0

        lines.append(f"  Total jobs processed: {processed}")
        lines.append(f"  Tasks created: {created_success}")
        lines.append(f"  Conversion rate: {success_rate:.1f}%")
        lines.append("")

        # Configuration parameters (supplementary info)
        lines.append("-" * 100)
        lines.append("Filtering configuration:")
        lines.append(f"  Max errors per job: {stats.get('max_count', 6)}")
        lines.append(f"  Min priority threshold: {stats.get('min_priority', 10)}")
        lines.append("")

        # Performance metrics
        lines.append("-" * 100)
        lines.append("Performance metrics:")
        lines.append(f"  Cache hit rate: {stats.get('cache_hit_rate', 0):.2%}")
        lines.append(f"  Cache size: {stats.get('cache_size', 0)}/{stats.get('cache_max_size', 5000)}")

        if stats.get('jobs_processed', 0) > 0:
            lines.append(f"  Average processing time:")
            lines.append(f"    - Build task filtering: {stats.get('avg_filter_time_ms', 0):.2f}ms")
            lines.append(f"    - Git URL extraction: {stats.get('avg_git_url_time_ms', 0):.2f}ms")
            lines.append(f"    - Error ID filtering: {stats.get('avg_errid_time_ms', 0):.2f}ms")
        lines.append("")

        # System health analysis
        lines.append("-" * 100)
        lines.append("System health analysis:")

        # Filter efficiency assessment
        if total_before > 0:
            filter_rate = (filtered_count / total_before) * 100
            if filter_rate > 85:
                lines.append(f"  [GOOD] Filter efficiency: excellent ({filter_rate:.1f}%) - noise effectively filtered")
            elif filter_rate > 70:
                lines.append(f"  [OK] Filter efficiency: good ({filter_rate:.1f}%)")
            else:
                lines.append(f"  [WARN] Filter efficiency: low ({filter_rate:.1f}%) - may need to adjust filtering rules")

        # Dedup rate assessment
        if total_candidates > 0:
            dedup_rate = (db_duplicate / total_candidates) * 100
            if dedup_rate > 95:
                lines.append(f"  [GOOD] Dedup rate: excellent ({dedup_rate:.1f}%) - mature system, few duplicate tasks")
            elif dedup_rate > 80:
                lines.append(f"  [OK] Dedup rate: good ({dedup_rate:.1f}%)")
            else:
                lines.append(f"  [GOOD] Dedup rate: normal ({dedup_rate:.1f}%) - found many new tasks")

        # Conversion rate assessment
        if processed > 0:
            if success_rate > 5:
                lines.append(f"  [GOOD] Conversion rate: normal ({success_rate:.1f}%) - found many new issues")
            elif success_rate > 0.5:
                lines.append(f"  [GOOD] Conversion rate: healthy ({success_rate:.1f}%) - mature and stable system")
            else:
                lines.append(f"  [GOOD] Conversion rate: stable ({success_rate:.1f}%) - very few new issues (normal for mature system)")

        # git_url missing warning
        if no_git_url > 0:
            lines.append(f"  [WARN] Found {no_git_url} tasks missing git_url, please check")

        lines.append("")
        lines.append("=" * 100)
        lines.append(f"Report generated at: {time.strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append("=" * 100)

        return "\n".join(lines)

    def write_report(self, stats: Dict, duration: float):
        """
        Generate and write report to producer_stats directory (organized by date)

        Args:
            stats: statistics data dictionary
            duration: execution duration (seconds)
        """
        # Generate report content
        report_content = self.generate_report(stats, duration)

        # Print to log
        logger.info("\n" + report_content)

        # Create daily subdirectory
        cycle_time = stats.get('cycle_start_time', int(time.time()))
        date_str = datetime.fromtimestamp(cycle_time).strftime('%Y-%m-%d')
        daily_dir = os.path.join(self.stats_base_dir, date_str)
        os.makedirs(daily_dir, exist_ok=True)

        # Write text file
        try:
            report_file = os.path.join(
                daily_dir,
                f"producer_report_{cycle_time}.txt"
            )

            with open(report_file, 'w', encoding='utf-8') as f:
                f.write(report_content)

            logger.info(f"Report saved to: {report_file}")

        except Exception as e:
            logger.error(f"Failed to write report file: {str(e)}")

        # Write JSON data (for programmatic analysis)
        try:
            json_file = os.path.join(
                daily_dir,
                f"producer_stats_{cycle_time}.json"
            )

            with open(json_file, 'w', encoding='utf-8') as f:
                json.dump(stats, f, indent=2, ensure_ascii=False)

            logger.info(f"Statistics data saved to: {json_file}")

        except Exception as e:
            logger.error(f"Failed to write statistics data: {str(e)}")

    def write_simple_summary(self, stats: Dict):
        """
        Write a short latest status summary to root directory (for quick viewing)

        Args:
            stats: statistics data dictionary
        """
        try:
            summary_file = os.path.join(self.stats_base_dir, "producer_latest.txt")

            cycle_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stats.get('cycle_start_time', time.time())))
            processed = stats.get('jobs_processed', 0)
            created = stats.get('tasks_created_success', 0)
            success_rate = (created / processed * 100) if processed > 0 else 0

            summary = f"""Latest producer run status
=====================
Run time: {cycle_time}
Jobs processed: {processed}
Tasks created: {created}
Conversion rate: {success_rate:.1f}%
=====================
"""

            with open(summary_file, 'w', encoding='utf-8') as f:
                f.write(summary)

            logger.info(f"Latest status summary updated: {summary_file}")

        except Exception as e:
            logger.error(f"Failed to write status summary: {str(e)}")
