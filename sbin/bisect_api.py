#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Bisect API client for error and performance bisect tasks."""

import os
import sys
import json
import argparse
import urllib.parse
from typing import Optional, Dict, Any

try:
    import requests
except ImportError:
    print("Error: the requests package is required")
    print("Run: pip3 install requests")
    sys.exit(1)


class BisectAPIClient:
    """Bisect API client."""

    def __init__(self, host: Optional[str] = None):
        self.host = host or os.environ.get('BISECT_API_HOST', 'localhost:9999')
        self.base_url = f"http://{self.host}/api/v1"
        self.session = requests.Session()
        self.session.headers.update({'Content-Type': 'application/json'})

        # ANSI color codes
        self.RED = '\033[0;31m'
        self.GREEN = '\033[0;32m'
        self.YELLOW = '\033[1;33m'
        self.BLUE = '\033[0;34m'
        self.NC = '\033[0m'  # Reset color

    def _print_colored(self, color: str, message: str):
        """Print a colored message."""
        print(f"{color}{message}{self.NC}")

    def _confirm_action(self, warning: str, assume_yes: bool = False) -> bool:
        """Confirm a potentially destructive action and avoid EOFError in non-interactive mode."""
        self._print_colored(self.YELLOW, warning)
        if assume_yes:
            return True

        try:
            confirm = input("Continue? (y/N): ")
        except EOFError:
            self._print_colored(self.RED, "Error: use --yes or -y in non-interactive environments")
            return False

        if confirm.lower() != 'y':
            print("Operation cancelled")
            return False

        return True

    def _make_request(self, method: str, endpoint: str,
                      params: Optional[Dict] = None,
                      json_data: Optional[Dict] = None) -> Optional[Dict]:
        """Send an HTTP request."""
        url = f"{self.base_url}{endpoint}"

        # Show request details
        self._print_colored(self.BLUE, f"Request: {method} {url}")
        if params:
            # URL encoding is handled automatically
            query_string = urllib.parse.urlencode(params)
            self._print_colored(self.BLUE, f"Params: {query_string}")
        if json_data:
            self._print_colored(self.BLUE, f"JSON: {json.dumps(json_data, ensure_ascii=False)}")

        try:
            response = self.session.request(
                method=method,
                url=url,
                params=params,  # requests handles URL encoding automatically
                json=json_data,
                timeout=30
            )

            self._print_colored(self.BLUE, f"Status: {response.status_code}")

            if response.status_code >= 200 and response.status_code < 300:
                self._print_colored(self.GREEN, "Success:")
                if response.content:
                    data = response.json()

                    # For task lists, move id to the front for readability.
                    if isinstance(data, dict) and 'tasks' in data and isinstance(data['tasks'], list):
                        reordered_tasks = []
                        for task in data['tasks']:
                            if isinstance(task, dict) and 'id' in task:
                                ordered_task = {'id': task['id']}
                                for key, value in task.items():
                                    if key != 'id':
                                        ordered_task[key] = value
                                reordered_tasks.append(ordered_task)
                            else:
                                reordered_tasks.append(task)
                        data['tasks'] = reordered_tasks

                    print(json.dumps(data, indent=2, ensure_ascii=False))
                    return data
                else:
                    print("(empty response)")
                    return {}
            else:
                self._print_colored(self.RED, "Request failed:")
                try:
                    error_data = response.json()
                    print(json.dumps(error_data, indent=2, ensure_ascii=False))
                except:
                    print(response.text)
                return None

        except requests.exceptions.ConnectionError:
            self._print_colored(self.RED, f"Error: unable to connect to {self.base_url}")
            self._print_colored(self.RED, "Check whether the service is running")
        except requests.exceptions.Timeout:
            self._print_colored(self.RED, "Error: request timed out")
        except Exception as e:
            self._print_colored(self.RED, f"Error: {str(e)}")

        return None

    def new_task(self, task_data: Dict[str, Any]) -> Optional[Dict]:
        """Create a new bisect task."""
        return self._make_request("POST", "/new_bisect_task", json_data=task_data)

    def list_tasks(self, status: Optional[str] = None,
                   error_id: Optional[str] = None,
                   bad_job_id: Optional[str] = None,
                   category: Optional[str] = None,
                   hours: Optional[int] = None,
                   git_url: Optional[str] = None,
                   task_id: Optional[str] = None,
                   task_ids: Optional[str] = None,
                   commit: Optional[str] = None,
                   limit: Optional[int] = None) -> Optional[Dict]:
        """List tasks with optional filters."""
        params = {}
        if status:
            params['status'] = status
        if error_id:
            params['error_id'] = error_id  # requests handles URL encoding automatically
        if bad_job_id:
            params['bad_job_id'] = bad_job_id
        if category:
            params['category'] = category
        if hours:
            params['hours'] = str(hours)
        if git_url:
            params['git_url'] = git_url
        if task_id:
            params['task_id'] = task_id
        if task_ids:
            params['task_ids'] = task_ids
        if commit:
            params['first_bad_commit'] = commit  # Map commit to first_bad_commit
        if limit:
            params['limit'] = str(limit)

        return self._make_request("GET", "/list_bisect_tasks", params=params)

    def delete_tasks(self, assume_yes: bool = False, **conditions) -> Optional[Dict]:
        """Delete tasks by filter conditions."""
        if not conditions:
            self._print_colored(self.RED, "Error: delete conditions are required")
            return None

        if not self._confirm_action(f"Warning: the following tasks will be deleted: {conditions}", assume_yes=assume_yes):
            return None

        return self._make_request("DELETE", "/delete_tasks", params=conditions)

    def reset_failed_tasks(self, assume_yes: bool = False) -> Optional[Dict]:
        """Reset failed tasks."""
        if not self._confirm_action("Warning: all failed tasks will be reset", assume_yes=assume_yes):
            return None

        return self._make_request("POST", "/reset_failed_tasks")

    def reset_processing_tasks(self, assume_yes: bool = False) -> Optional[Dict]:
        """Reset processing tasks to wait."""
        if not self._confirm_action("Warning: all processing tasks will be reset to wait", assume_yes=assume_yes):
            return None

        return self._make_request("POST", "/reset_processing_tasks")

    def reset_verifying_tasks(self, assume_yes: bool = False) -> Optional[Dict]:
        """Reset verifying tasks to wait."""
        if not self._confirm_action("Warning: all verifying tasks will be reset to wait", assume_yes=assume_yes):
            return None

        return self._make_request("POST", "/reset_verifying_tasks")

    def reset_pending_verification_tasks(self, assume_yes: bool = False) -> Optional[Dict]:
        """Reset pending_verification tasks to wait."""
        if not self._confirm_action(
            "Warning: all pending_verification tasks will be reset to wait",
            assume_yes=assume_yes
        ):
            return None

        return self._make_request("POST", "/reset_pending_verification_tasks")

    def cleanup_orphaned_verifying(self, assume_yes: bool = False) -> Optional[Dict]:
        """Clean up orphaned verifying tasks."""
        if not self._confirm_action(
            "Warning: orphaned verifying tasks will be cleaned up",
            assume_yes=assume_yes
        ):
            return None

        return self._make_request("POST", "/cleanup_orphaned_verifying")

    def set_tasks_to_verifying(self, task_ids: list, assume_yes: bool = False) -> Optional[Dict]:
        """Manually set one or more tasks to verifying."""
        warning = (
            f"Warning: {len(task_ids)} tasks will be set to 'verifying'\n"
            f"Task IDs: {task_ids}"
        )
        if not self._confirm_action(warning, assume_yes=assume_yes):
            return None
        
        json_data = {"task_ids": task_ids}
        return self._make_request("POST", "/set_tasks_to_verifying", json_data=json_data)

    def reset_task(self, task_id: str) -> Optional[Dict]:
        """Reset a task by ID to wait (deprecated, use reset_tasks)."""
        if not task_id.isdigit():
            self._print_colored(self.RED, "Error: task ID must be numeric")
            return None

        return self._make_request("POST", f"/reset_task?id={task_id}")

    def reset_tasks(self, assume_yes: bool = False, **conditions) -> Optional[Dict]:
        """Reset tasks to wait by filter conditions."""
        if not conditions:
            self._print_colored(self.RED, "Error: reset conditions are required")
            return None

        if not self._confirm_action(f"Warning: matching tasks will be reset: {conditions}", assume_yes=assume_yes):
            return None

        return self._make_request("POST", "/reset_tasks", params=conditions)

    def thread_pool_status(self) -> Optional[Dict]:
        """Get thread pool status."""
        return self._make_request("GET", "/thread_pool_status")

    def verification_status(self) -> Optional[Dict]:
        """Get verification queue status."""
        return self._make_request("GET", "/verification_status")

    def toggle_producer(self, enable: bool) -> Optional[Dict]:
        """Enable or disable the producer."""
        state = "enable" if enable else "disable"
        return self._make_request("POST", f"/toggle_producer?state={state}")

    def producer_status(self) -> Optional[Dict]:
        """Get producer status."""
        return self._make_request("GET", "/producer_status")

    def toggle_consumer(self, enable: bool) -> Optional[Dict]:
        """Enable or disable the consumer workers."""
        state = "enable" if enable else "disable"
        return self._make_request("POST", f"/toggle_consumer?state={state}")

    def consumer_status(self) -> Optional[Dict]:
        """Get consumer status."""
        return self._make_request("GET", "/consumer_status")

    def trigger_producer_run(self, force: bool = False) -> Optional[Dict]:
        """Trigger a producer run manually."""
        params = {'force': 'true'} if force else {}
        return self._make_request("POST", "/trigger_producer_run", params=params)

    # Pool monitoring methods
    def pool_status(self) -> Optional[Dict]:
        """Get repository pool status."""
        return self._make_request("GET", "/pool/status")

    def pool_cleanup(self, dry_run: bool = True, max_age_days: Optional[float] = None) -> Optional[Dict]:
        """Trigger workspace cleanup."""
        data = {"dry_run": dry_run}
        if max_age_days is not None:
            data["max_age_days"] = max_age_days
        return self._make_request("POST", "/pool/cleanup", json_data=data)

    def pool_stats(self) -> Optional[Dict]:
        """Get pool monitor statistics."""
        return self._make_request("GET", "/pool/stats")

    def pool_verify(self) -> Optional[Dict]:
        """Verify workspace consistency."""
        return self._make_request("POST", "/pool/verify")

    def pool_monitor_start(self) -> Optional[Dict]:
        """Start the pool monitor thread."""
        return self._make_request("POST", "/pool/monitor/start")

    def pool_monitor_stop(self) -> Optional[Dict]:
        """Stop the pool monitor thread."""
        return self._make_request("POST", "/pool/monitor/stop")

    def _make_silent_request(self, method: str, endpoint: str,
                             params: Optional[Dict] = None,
                             json_data: Optional[Dict] = None) -> Optional[Dict]:
        """Send an HTTP request without printing request/response details."""
        url = f"{self.base_url}{endpoint}"
        try:
            response = self.session.request(
                method=method,
                url=url,
                params=params,
                json=json_data,
                timeout=10
            )
            if 200 <= response.status_code < 300:
                if response.content:
                    return response.json()
                return {}
        except Exception:
            pass
        return None

    @staticmethod
    def _status_column_label(status: str) -> str:
        """Keep the status table readable while preserving full status semantics."""
        labels = {
            'pending_verification': 'pending_ver',
        }
        return labels.get(status, status)

    @staticmethod
    def _count_section_entries(text: str, section_name: str) -> int:
        """Count numeric entries in a @section.keys block from scheduler debug output."""
        import re

        pattern = rf'@{re.escape(section_name)}\.keys:\s*\['
        match = re.search(pattern, text)
        if not match:
            return 0

        start = match.end()
        depth = 1
        pos = start
        while pos < len(text) and depth > 0:
            if text[pos] == '[':
                depth += 1
            elif text[pos] == ']':
                depth -= 1
            pos += 1

        block = text[start:pos]
        return len(re.findall(r'\d{10,}', block))

    @staticmethod
    def _extract_keys(text: str, section_name: str) -> list:
        """Extract quoted string keys from a @section.keys block."""
        import re

        pattern = rf'@{re.escape(section_name)}\.keys:\s*\[(.*?)\]'
        match = re.search(pattern, text, re.DOTALL)
        if not match:
            return []
        return re.findall(r'"([^"]+)"', match.group(1))

    def _print_scheduler_status(self):
        """Best-effort query of the scheduler dispatch endpoint."""
        scheduler_host = os.environ.get('SCHEDULER_HOST', 'localhost')
        scheduler_port = os.environ.get('SCHEDULER_PORT', '3000')
        url = f"http://{scheduler_host}:{scheduler_port}/scheduler/v1/debug/dispatch"
        try:
            resp = self.session.get(url, timeout=5)
            if resp.status_code != 200:
                return
            text = resp.text

            submit_count = self._count_section_entries(text, 'jobs_cache_in_submit')
            running_count = self._count_section_entries(text, 'jobs_cache')
            providers = self._extract_keys(text, 'provider_sessions')
            hw_machines = self._extract_keys(text, 'hw_machine_channels')

            print()
            print("Scheduler dispatch queue:")
            print(f"  jobs waiting (submit): {submit_count}")
            print(f"  jobs active (cached) : {running_count}")
            print(f"  VM/container providers: {len(providers)}")
            for provider in providers:
                print(f"    - {provider}")
            print(f"  HW machine channels  : {len(hw_machines)}")
            for machine in hw_machines:
                print(f"    - {machine}")
        except Exception:
            pass

    def _print_job_completion_trend(self):
        """Show a local best-effort recent completion trend from result directories."""
        import subprocess
        from datetime import datetime, timedelta

        result_root = os.environ.get('RESULT_ROOT', '/result')
        if not os.path.isdir(result_root):
            return

        print()
        print("Recent job completion trend (last 7 days):")
        print(f"  {'date':<12} {'total':>6} {'bisect':>7} {'machines'}")
        print("  " + "-" * 56)

        today = datetime.now()
        for days_ago in range(6, -1, -1):
            day = today - timedelta(days=days_ago)
            day_str = day.strftime('%Y-%m-%d')

            try:
                cmd = [
                    'find', '-L', result_root, '-maxdepth', '8',
                    '-path', f'*/{day_str}/*/job.yaml', '-type', 'f'
                ]
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
                all_jobs = [path for path in proc.stdout.strip().split('\n') if path]
                total = len(all_jobs)

                if total == 0:
                    print(f"  {day_str:<12} {0:>6} {0:>7}")
                    continue

                bisect_count = 0
                machines = set()
                for job_path in all_jobs:
                    try:
                        with open(job_path, 'r', errors='replace') as file_obj:
                            content = file_obj.read(4096)
                        if 'bad_job_id' in content:
                            bisect_count += 1
                        for line in content.split('\n'):
                            if line.startswith('testbox:'):
                                machines.add(line.split(':', 1)[1].strip())
                                break
                    except (OSError, IOError):
                        continue

                machines_str = ', '.join(sorted(machines)) if machines else '-'
                if len(machines_str) > 40:
                    machines_str = f"{len(machines)} machines"
                print(f"  {day_str:<12} {total:>6} {bisect_count:>7}  {machines_str}")
            except Exception:
                print(f"  {day_str:<12}      ?       ?")

    def status(self) -> Optional[Dict]:
        """Print a one-screen overview of bisect system health."""
        overview = self._make_silent_request("GET", "/status_overview")
        if not overview:
            self._print_colored(self.RED, "Error: unable to fetch task status overview")
            return None

        statuses = overview.get('statuses') or [
            'success', 'failed', 'processing', 'verifying', 'wait', 'pending_verification'
        ]
        categories = overview.get('categories') or ['build', 'benchmark', 'function']
        status_counts = overview.get('task_status_counts') or {}
        category_counts = overview.get('category_status_counts') or {}

        print("=" * 72)
        print("  BISECT SYSTEM STATUS")
        print("=" * 72)
        print()
        print("Task status overview:")
        for status in statuses:
            count = int(status_counts.get(status, 0) or 0)
            bar = '#' * min(count // 10, 40)
            print(f"  {status:<22} {count:>6}  {bar}")
        print(f"  {'TOTAL':<22} {int(overview.get('task_total', 0) or 0):>6}")

        print()
        print("Breakdown by category:")
        header = f"  {'category':<14}"
        for status in statuses:
            header += f" {self._status_column_label(status):>12}"
        header += f" {'total':>8} {'done':>6} {'rate':>7}"
        print(header)
        print("  " + "-" * (len(header) - 2))
        for category in categories:
            counts = category_counts.get(category, {})
            total = 0
            row = f"  {category:<14}"
            for status in statuses:
                count = int(counts.get(status, 0) or 0)
                total += count
                row += f" {count:>12}"
            done = int(counts.get('success', 0) or 0) + int(counts.get('failed', 0) or 0)
            rate = f"{int(counts.get('success', 0) or 0) / done * 100:.0f}%" if done > 0 else "-"
            row += f" {total:>8} {done:>6} {rate:>7}"
            print(row)

        verification = self._make_silent_request("GET", "/verification_status")
        if verification:
            print()
            print("Verification queue:")
            print(f"  verifying (active)   : {verification.get('verifying', '?')}")
            print(f"  pending verification : {verification.get('pending_verification', '?')}")
            print(
                "  verified (total)     : "
                f"{verification.get('verification_status_counts', {}).get('verified', '?')}"
            )
            config = verification.get('config', {})
            if config:
                print(f"  max_verifying_tasks  : {config.get('max_verifying_tasks', '?')}")
                print(f"  timeout_hours        : {config.get('verification_timeout_hours', '?')}")

        thread_pool = self._make_silent_request("GET", "/thread_pool_status")
        if thread_pool:
            print()
            print("Thread pool:")
            print(
                f"  active / max         : "
                f"{thread_pool.get('active_threads', '?')} / {thread_pool.get('max_workers', '?')}"
            )
            print(f"  pending in queue     : {thread_pool.get('pending_tasks', '?')}")

        producer = self._make_silent_request("GET", "/producer_status")
        if producer:
            print()
            alive = any(item.get('is_alive') for item in producer.get('producer_threads', []))
            print(
                f"Producer: {'enabled' if producer.get('producer_enabled') else 'disabled'}"
                f"  |  {'alive' if alive else 'DEAD'}"
            )

        consumer = self._make_silent_request("GET", "/consumer_status")
        if consumer:
            print()
            print(
                f"Consumer: {'enabled' if consumer.get('consumer_enabled') else 'disabled'}"
                f"  |  {'accepting' if consumer.get('accepting_new_tasks') else 'paused'}"
            )
            pause_reason = consumer.get('pause_reason')
            if pause_reason:
                print(f"  pause_reason         : {pause_reason}")
            if 'startup_delay_remaining_seconds' in consumer:
                print(
                    "  startup_delay_left   : "
                    f"{consumer.get('startup_delay_remaining_seconds', '?')}"
                )

        self._print_scheduler_status()
        self._print_job_completion_trend()

        print()
        print("=" * 72)
        return overview


def add_common_filter_args(parser, include_limit=False):
    """Add common filter arguments to a parser."""
    parser.add_argument('--id', help='Task ID')
    parser.add_argument('--error_id', help='Full error ID (exact match)')
    parser.add_argument('--bad_job_id', help='Bad job ID')
    parser.add_argument('--git_url', help='Git repository URL')
    parser.add_argument('--category', help='Task category (build/function/benchmark)')
    parser.add_argument('--status', help='Task status (wait/processing/success/failed/verifying/pending_verification)')
    parser.add_argument('--commit', help='Filter by first_bad_commit (full or short SHA)')

    if include_limit:
        parser.add_argument('--limit', type=int, help='Maximum number of results to return (default: 100000)')


def add_yes_arg(parser):
    """Add a shared non-interactive confirmation bypass flag."""
    parser.add_argument('--yes', '-y', action='store_true', help='Skip interactive confirmation')


def build_filter_conditions(args):
    """Build filter conditions from parsed arguments."""
    conditions = {}
    if hasattr(args, 'id') and args.id:
        conditions['task_id'] = args.id  # Map id to task_id
    if hasattr(args, 'error_id') and args.error_id:
        conditions['error_id'] = args.error_id
    if hasattr(args, 'bad_job_id') and args.bad_job_id:
        conditions['bad_job_id'] = args.bad_job_id
    if hasattr(args, 'git_url') and args.git_url:
        conditions['git_url'] = args.git_url
    if hasattr(args, 'category') and args.category:
        conditions['category'] = args.category
    if hasattr(args, 'status') and args.status:
        conditions['status'] = args.status
    if hasattr(args, 'commit') and args.commit:
        conditions['first_bad_commit'] = args.commit  # Map commit to first_bad_commit
    return conditions


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Bisect API client for error and performance bisect tasks',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create a new task
  %(prog)s new_task --bad_job_id 123456 --error_id "compile_error"
  %(prog)s new_task --bad_job_id 123456 --metric "hackbench.throughput"
  %(prog)s new_task -f task.json
  %(prog)s new_task -j '{"bad_job_id":"123456","error_id":"test.error"}'

  # List tasks (supports combined filters)
  %(prog)s list_tasks
  %(prog)s list_tasks --status success
  %(prog)s list_tasks --error_id "stderr.eid.fs/#p/vfs_file.c:warning"
  %(prog)s list_tasks --bad_job_id 12345 --limit 10
  %(prog)s list_tasks --status failed --category build
  %(prog)s list_tasks --category function --hours 24
  %(prog)s list_tasks --git_url "https://github.com/torvalds/linux.git"
  %(prog)s list_tasks --task_ids 12345,67890
  %(prog)s list_tasks --commit bbaaa756ad25
  %(prog)s list_tasks --commit bbaaa756ad25c0e792fcd195d32acd5715f76b12

  # Delete tasks (supports combined filters)
  %(prog)s delete_tasks --id 1001
  %(prog)s delete_tasks --error_id "test.error"
  %(prog)s delete_tasks --commit bbaaa756ad25
  %(prog)s delete_tasks --status failed --category build

  # Reset tasks (supports combined filters)
  %(prog)s reset_failed
  %(prog)s reset_processing
  %(prog)s reset_verifying
  %(prog)s reset_pending_verification
  %(prog)s cleanup_orphaned_verifying
  %(prog)s reset_tasks --id 12345
  %(prog)s reset_tasks --commit bbaaa756ad25
  %(prog)s reset_tasks --status failed --category build
  %(prog)s set_verifying --ids 12345 67890

  # Producer control
  %(prog)s enable_producer
  %(prog)s disable_producer
  %(prog)s producer_status
  %(prog)s trigger_producer

  # System overview
  %(prog)s status

  # Consumer control
  %(prog)s enable_consumer
  %(prog)s disable_consumer
  %(prog)s consumer_status

  # Thread and verification queue status
  %(prog)s thread_status
  %(prog)s verification_status

  # Pool management commands
  %(prog)s pool_status
  %(prog)s pool_cleanup --dry-run
  %(prog)s pool_cleanup --max-age-days 0.5
  %(prog)s pool_stats
  %(prog)s pool_verify
  %(prog)s pool_monitor_start
  %(prog)s pool_monitor_stop

Environment variables:
  BISECT_API_HOST - API server address (default: localhost:9999)

Notes:
  • Special characters such as #, &, and spaces are URL-encoded automatically
  • error_id and metric are mutually exclusive
  • list_tasks supports combined filters such as status, category, and hours
  • --error_id uses exact matching; pass the full error_id value
  • Use -h to see detailed help for each command
"""
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # new_task command
    new_task_parser = subparsers.add_parser(
        'new_task',
        help='Create a new bisect task',
        description='Create a new bisect task for error or performance regressions',
        epilog="""
Examples:
  # Error bisect task
  %(prog)s --bad_job_id 123456 --error_id "compile_error"
  %(prog)s --bad_job_id 123456 --error_id "stderr.eid.fs/#p/vfs_file.c:warning"

  # Performance bisect task
  %(prog)s --bad_job_id 123456 --metric "hackbench.throughput"
  %(prog)s --bad_job_id 123456 --metric "boot.time" --git_url "https://github.com/torvalds/linux.git"

  # Read task data from a JSON file
  %(prog)s -f task.json

  # Pass task data as a JSON string
  %(prog)s -j '{"bad_job_id":"123456","error_id":"test.error"}'
"""
    )
    new_task_group = new_task_parser.add_mutually_exclusive_group(required=False)
    new_task_group.add_argument('-f', '--file', help='Read task data from a JSON file')
    new_task_group.add_argument('-j', '--json', help='Pass task data as a JSON string')
    new_task_parser.add_argument('--bad_job_id', help='Bad job ID (required unless -f or -j is used)')
    new_task_parser.add_argument('--error_id', help='Error ID for an error bisect task')
    new_task_parser.add_argument('--metric', help='Performance metric name for a performance bisect task')
    new_task_parser.add_argument('--git_url', help='Git repository URL (optional)')
    new_task_parser.add_argument('--good_commit', help='Known good commit SHA (optional)')

    # list_tasks command
    list_parser = subparsers.add_parser(
        'list_tasks',
        help='List bisect tasks',
        description='List bisect tasks with multiple filter options',
        epilog="""
Examples:
  # List all tasks
  %(prog)s

  # Filter by status
  %(prog)s --status success
  %(prog)s --status failed

  # Filter by full error_id (exact match, special characters supported)
  %(prog)s --error_id "stderr.eid.fs/#p/vfs_file.c:warning"
  %(prog)s --error_id "makepkg.eid.fs/#p/vfs_file.c:warning:Excess-function-parameter"

  # Filter by category
  %(prog)s --category build
  %(prog)s --category function

  # Filter by time
  %(prog)s --hours 24
  %(prog)s --hours 48 --status failed

  # Filter by Git repository
  %(prog)s --git_url "https://github.com/torvalds/linux.git"

  # Filter by task ID
  %(prog)s --task_id 12345
  %(prog)s --task_ids 12345,67890,99999

  # Combined filters
  %(prog)s --status wait --error_id "test.error" --limit 10
  %(prog)s --bad_job_id 12345 --status success
  %(prog)s --status failed --category build
  %(prog)s --category function --hours 24 --status failed
  %(prog)s --git_url "https://github.com/torvalds/linux.git" --status success

Notes:
  • error_id uses exact matching; pass the full error_id value
  • Special characters in error_id are URL-encoded automatically
"""
    )
    # list_tasks uses common filter args plus task_id/task_ids/hours
    list_parser.add_argument('--task_id', help='Filter by a single task ID')
    list_parser.add_argument('--task_ids', help='Filter by multiple task IDs (comma-separated, e.g. 12345,67890)')
    list_parser.add_argument('--hours', type=int, help='Filter tasks updated within the last N hours')
    add_common_filter_args(list_parser, include_limit=True)

    # delete_tasks command
    delete_parser = subparsers.add_parser(
        'delete_tasks',
        help='Delete tasks that match filters',
        description='Delete bisect tasks that match the specified filters',
        epilog="""
Examples:
  # Delete by ID
  %(prog)s --id 1001

  # Delete by full error_id
  %(prog)s --error_id "test.error"

  # Delete by bad_job_id
  %(prog)s --bad_job_id 12345

  # Delete by commit
  %(prog)s --commit bbaaa756ad25
  %(prog)s --commit bbaaa756ad25c0e792fcd195d32acd5715f76b12

  # Delete by status and category
  %(prog)s --status failed --category build
  %(prog)s --status wait --category function

  # Combined filters (AND)
  %(prog)s --error_id "test.error" --bad_job_id 12345
  %(prog)s --git_url "https://github.com/torvalds/linux.git" --status failed
  %(prog)s --commit bbaaa756ad25 --status failed

Warning: delete operations are irreversible
"""
    )
    # delete_tasks uses the common filter args
    add_common_filter_args(delete_parser)
    add_yes_arg(delete_parser)

    # Other commands
    reset_failed_parser = subparsers.add_parser('reset_failed', help='Reset all failed tasks to wait')
    add_yes_arg(reset_failed_parser)
    reset_processing_parser = subparsers.add_parser('reset_processing', help='Reset all processing tasks to wait')
    add_yes_arg(reset_processing_parser)
    reset_verifying_parser = subparsers.add_parser('reset_verifying', help='Reset all verifying tasks to wait')
    add_yes_arg(reset_verifying_parser)
    reset_pending_parser = subparsers.add_parser('reset_pending_verification', help='Reset all pending_verification tasks to wait')
    add_yes_arg(reset_pending_parser)
    cleanup_verifying_parser = subparsers.add_parser('cleanup_orphaned_verifying', help='Clean up orphaned verifying tasks')
    add_yes_arg(cleanup_verifying_parser)

    set_verifying_parser = subparsers.add_parser(
        'set_verifying',
        help='Set one or more tasks to verifying',
        description='Manually set one or more tasks to verifying so the verification consumer can process them.',
        epilog="""
Examples:
  # Set a single task
  %(prog)s --ids 12345

  # Set multiple tasks
  %(prog)s --ids 12345 67890
"""
    )
    set_verifying_parser.add_argument('--ids', required=True, nargs='+', help='Task IDs to set to verifying')
    add_yes_arg(set_verifying_parser)

    # reset_tasks command
    reset_tasks_parser = subparsers.add_parser(
        'reset_tasks',
        help='Reset tasks that match filters to wait',
        description='Reset bisect tasks that match the specified filters to wait (failed or processing only)',
        epilog="""
Examples:
  # Reset by task ID
  %(prog)s --id 12345

  # Reset by full error_id
  %(prog)s --error_id "test.error"

  # Reset by commit
  %(prog)s --commit bbaaa756ad25

  # Reset by status
  %(prog)s --status failed

  # Combined filters
  %(prog)s --status failed --category build
  %(prog)s --git_url "https://github.com/torvalds/linux.git" --status processing

Note: only failed or processing tasks can be reset
"""
    )
    # reset_tasks uses the common filter args
    add_common_filter_args(reset_tasks_parser)
    add_yes_arg(reset_tasks_parser)

    subparsers.add_parser('status', help='Show a one-screen bisect system overview')
    subparsers.add_parser('thread_status', help='Show thread pool status')
    subparsers.add_parser('verification_status', help='Show verification queue status')
    subparsers.add_parser('enable_producer', help='Enable the background producer')
    subparsers.add_parser('disable_producer', help='Disable the background producer')
    subparsers.add_parser('producer_status', help='Show producer status')
    trigger_parser = subparsers.add_parser('trigger_producer', help='Trigger a producer run manually')
    trigger_parser.add_argument('--force', action='store_true', help='Force a run even if one already ran today')

    subparsers.add_parser('enable_consumer', help='Enable BisectConsumer + SuccessTaskValidator')
    subparsers.add_parser('disable_consumer', help='Disable BisectConsumer + SuccessTaskValidator')
    subparsers.add_parser('consumer_status', help='Show consumer status')

    # Pool monitoring commands
    subparsers.add_parser('pool_status', help='Show repository pool status')

    pool_cleanup_parser = subparsers.add_parser('pool_cleanup', help='Trigger workspace cleanup')
    pool_cleanup_parser.add_argument('--dry-run', action='store_true', default=True, help='Preview only')
    pool_cleanup_parser.add_argument('--execute', action='store_true', help='Execute cleanup')
    pool_cleanup_parser.add_argument('--max-age-days', type=float, help='Maximum workspace age in days (default: 7)')

    subparsers.add_parser('pool_stats', help='Show pool monitor statistics')
    subparsers.add_parser('pool_verify', help='Verify workspace consistency')

    subparsers.add_parser('pool_monitor_start', help='Start the pool monitor thread')
    subparsers.add_parser('pool_monitor_stop', help='Stop the pool monitor thread')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    # Create the client
    client = BisectAPIClient()

    # Dispatch the command
    if args.command == 'new_task':
        if args.file:
            with open(args.file, 'r') as f:
                task_data = json.load(f)
        elif args.json:
            task_data = json.loads(args.json)
        else:
            # Build task data from CLI arguments
            task_data = {'bad_job_id': args.bad_job_id}

            if args.error_id and args.metric:
                print("Error: --error_id and --metric are mutually exclusive")
                return
            elif args.error_id:
                task_data['error_id'] = args.error_id
            elif args.metric:
                task_data['bisect_metric'] = args.metric
            else:
                print("Error: either --error_id or --metric is required")
                return

            if args.git_url:
                task_data['git_url'] = args.git_url
            if args.good_commit:
                task_data['good_commit'] = args.good_commit

        client.new_task(task_data)

    elif args.command == 'list_tasks':
        task_id = args.task_id or getattr(args, 'id', None)
        client.list_tasks(
            status=args.status,
            error_id=args.error_id,
            bad_job_id=args.bad_job_id,
            category=args.category,
            hours=args.hours,
            git_url=args.git_url,
            task_id=task_id,
            task_ids=args.task_ids,
            commit=args.commit,
            limit=args.limit
        )

    elif args.command == 'delete_tasks':
        conditions = build_filter_conditions(args)
        client.delete_tasks(assume_yes=args.yes, **conditions)

    elif args.command == 'reset_failed':
        client.reset_failed_tasks(assume_yes=args.yes)
    elif args.command == 'reset_processing':
        client.reset_processing_tasks(assume_yes=args.yes)
    elif args.command == 'reset_verifying':
        client.reset_verifying_tasks(assume_yes=args.yes)
    elif args.command == 'reset_pending_verification':
        client.reset_pending_verification_tasks(assume_yes=args.yes)
    elif args.command == 'cleanup_orphaned_verifying':
        client.cleanup_orphaned_verifying(assume_yes=args.yes)
    elif args.command == 'set_verifying':
        client.set_tasks_to_verifying(args.ids, assume_yes=args.yes)
    elif args.command == 'reset_tasks':
        # New plural form, using common filter conditions
        conditions = build_filter_conditions(args)
        client.reset_tasks(assume_yes=args.yes, **conditions)
    elif args.command == 'status':
        client.status()
    elif args.command == 'thread_status':
        client.thread_pool_status()
    elif args.command == 'verification_status':
        client.verification_status()
    elif args.command == 'enable_producer':
        client.toggle_producer(True)
    elif args.command == 'disable_producer':
        client.toggle_producer(False)
    elif args.command == 'producer_status':
        client.producer_status()
    elif args.command == 'trigger_producer':
        client.trigger_producer_run(force=args.force)
    elif args.command == 'enable_consumer':
        client.toggle_consumer(True)
    elif args.command == 'disable_consumer':
        client.toggle_consumer(False)
    elif args.command == 'consumer_status':
        client.consumer_status()

    # Pool monitoring commands
    elif args.command == 'pool_status':
        client.pool_status()
    elif args.command == 'pool_cleanup':
        dry_run = not args.execute
        client.pool_cleanup(dry_run=dry_run, max_age_days=getattr(args, 'max_age_days', None))
    elif args.command == 'pool_stats':
        client.pool_stats()
    elif args.command == 'pool_verify':
        client.pool_verify()
    elif args.command == 'pool_monitor_start':
        client.pool_monitor_start()
    elif args.command == 'pool_monitor_stop':
        client.pool_monitor_stop()


if __name__ == '__main__':
    main()
