#!/usr/bin/env python3
"""
Utility script to submit bisect tasks via API in batches.

Loads tasks from `new_bisect_tasks.txt` and submits them to exercise
creation, deduplication, and pending-verification flows.
"""

import os
import sys
import time
import json
import traceback
import requests
from typing import Dict, List, Tuple
from collections import defaultdict

# Add paths for imports
sys.path.append(os.environ['CCI_SRC'] + '/container/bisect/lib')
from log_config import logger

class APITaskSubmitter:
    def __init__(self, api_base_url: str = None, task_file_path: str = None):
        """Initialize API task submitter."""
        self.api_base_url = api_base_url or "http://localhost:5000"
        self.task_file_path = task_file_path or "/home/shiptux/git/gitee/compass-ci/new_bisect_tasks.txt"

        # API endpoints
        self.submit_endpoint = f"{self.api_base_url}/bisect/task"

        # Statistics
        self.stats = {
            'total_tasks': 0,
            'submitted': 0,
            'duplicates': 0,
            'pending_verification': 0,
            'created': 0,
            'errors': 0,
            'verification_tasks': []
        }

        logger.info(f"API submitter initialized | api: {self.api_base_url} | file: {self.task_file_path}")

    def load_tasks(self) -> List[Tuple[str, str]]:
        """Load tasks from the input file."""
        tasks = []
        try:
            with open(self.task_file_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue

                    parts = line.split(',', 1)
                    if len(parts) == 2:
                        job_id, error_id = parts
                        tasks.append((job_id.strip(), error_id.strip()))

            logger.info(f"Loaded {len(tasks)} tasks")
            self.stats['total_tasks'] = len(tasks)
            return tasks

        except Exception as e:
            logger.error(f"Failed to load task file: {str(e)}")
            return []

    def submit_task(self, job_id: str, error_id: str, dry_run: bool = False) -> Dict:
        """Submit one task to the API."""
        task_data = {
            "bad_job_id": job_id,
            "error_id": error_id
        }

        if dry_run:
            logger.debug(f"[DRY RUN] submit task | job_id: {job_id} | error_id: {error_id[:50]}...")
            return {"status": "dry_run", "message": "Dry run mode"}

        try:
            response = requests.post(
                self.submit_endpoint,
                json=task_data,
                headers={"Content-Type": "application/json"},
                timeout=10
            )

            if response.status_code == 200:
                result = response.json()
                return result
            else:
                logger.error(f"API error | status: {response.status_code} | response: {response.text}")
                return {"status": "error", "message": f"HTTP {response.status_code}"}

        except requests.exceptions.RequestException as e:
            logger.error(f"save results failed: {str(e)}")
            return {"status": "error", "message": str(e)}
        except Exception as e:
            logger.error(f"submit task exception: {str(e)}")
            return {"status": "error", "message": str(e)}

    def run_submission(self, dry_run: bool = False, batch_size: int = 10, delay: float = 0.1):
        """Submit tasks in batches."""
        logger.info("=" * 80)
        logger.info(f"Start task submission {'[DRY RUN]' if dry_run else ''}")
        logger.info("=" * 80)

        # 1. Load tasks
        tasks = self.load_tasks()
        if not tasks:
            logger.error("No tasks loaded")
            return

        # 2. Submit tasks
        start_time = time.time()
        batch_count = 0

        for i, (job_id, error_id) in enumerate(tasks, 1):
            # Submit task
            result = self.submit_task(job_id, error_id, dry_run)

            self.stats['submitted'] += 1

            status = result.get('status')
            if status == 'duplicate':
                self.stats['duplicates'] += 1
                logger.debug(f"[{i}/{len(tasks)}] duplicate task: {error_id[:50]}...")
            elif status == 'pending_verification':
                self.stats['pending_verification'] += 1
                logger.info(f"[{i}/{len(tasks)}] pending verification: {error_id[:50]}... | {result.get('message', '')}")
                self.stats['verification_tasks'].append({
                    'job_id': job_id,
                    'error_id': error_id,
                    'message': result.get('message', '')
                })
            elif status == 'created':
                self.stats['created'] += 1
                logger.info(f"[{i}/{len(tasks)}] created: {error_id[:50]}...")
            else:
                self.stats['errors'] += 1
                logger.warning(f"[{i}/{len(tasks)}] error: {error_id[:50]}... | {result.get('message', '')}")

            batch_count += 1
            if batch_count >= batch_size:
                # Batch boundary pause
                time.sleep(delay)
                batch_count = 0

                # Progress report
                elapsed = time.time() - start_time
                rate = i / elapsed
                eta = (len(tasks) - i) / rate if rate > 0 else 0
                logger.info(
                    f"Progress: {i}/{len(tasks)} ({i/len(tasks)*100:.1f}%) | "
                    f"Rate: {rate:.1f} tasks/s | ETA: {eta:.0f}s"
                )

        elapsed_time = time.time() - start_time

        # 3. Print summary
        self.print_results(elapsed_time)

        # 4. Save output files
        self.save_results()

    def print_results(self, elapsed_time: float):
        """Print submission summary."""
        logger.info("=" * 80)
        logger.info("Task submission summary")
        logger.info("=" * 80)

        logger.info(f"Total tasks: {self.stats['total_tasks']}")
        logger.info(f"Submitted tasks: {self.stats['submitted']}")
        logger.info(f"Elapsed: {elapsed_time:.2f} s")
        logger.info(f"Throughput: {self.stats['submitted']/elapsed_time:.1f} tasks/s")

        logger.info("-" * 40)
        logger.info("Task status stats:")
        logger.info(f"  - duplicate(existing): {self.stats['duplicates']} ({self.stats['duplicates']/self.stats['submitted']*100:.1f}%)")
        logger.info(f"  - pending verification: {self.stats['pending_verification']} ({self.stats['pending_verification']/self.stats['submitted']*100:.1f}%)")
        logger.info(f"  - created: {self.stats['created']} ({self.stats['created']/self.stats['submitted']*100:.1f}%)")
        logger.info(f"  - errors: {self.stats['errors']} ({self.stats['errors']/self.stats['submitted']*100:.1f}%)")

        if self.stats['pending_verification'] > 0:
            logger.info("-" * 40)
            logger.info(f"* {self.stats['pending_verification']} tasks entered verification")
            logger.info("These tasks will be processed by verification consumers.")

            # Show first 5 verification tasks
            if self.stats['verification_tasks']:
                logger.info("\nVerification task examples (first 5):")
                for i, task in enumerate(self.stats['verification_tasks'][:5], 1):
                    logger.info(f"  {i}. {task['error_id']}")
                    logger.info(f"     {task['message']}")

    def save_results(self):
        """Save submission results to files."""
        output_dir = "/home/shiptux/git/gitee/compass-ci/container/bisect/logs"
        os.makedirs(output_dir, exist_ok=True)

        timestamp = time.strftime("%Y%m%d_%H%M%S")
        output_file = os.path.join(output_dir, f"api_submission_results_{timestamp}.json")

        try:
            with open(output_file, 'w') as f:
                json.dump(self.stats, f, indent=2, ensure_ascii=False)

            logger.info(f"\nSaved results to: {output_file}")

            # Save pending verification task list
            if self.stats['verification_tasks']:
                verify_file = os.path.join(output_dir, f"pending_verification_{timestamp}.json")
                with open(verify_file, 'w') as f:
                    json.dump(self.stats['verification_tasks'], f, indent=2, ensure_ascii=False)
                logger.info(f"Saved verification task list to: {verify_file}")

        except Exception as e:
            logger.error(f"save results failed: {str(e)}")


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Submit bisect tasks via API")
    parser.add_argument("--api-url", default="http://localhost:5000",
                        help="API base URL (default: http://localhost:5000)")
    parser.add_argument("--task-file", default="/home/shiptux/git/gitee/compass-ci/new_bisect_tasks.txt",
                        help="Path to task input file")
    parser.add_argument("--dry-run", action="store_true",
                        help="Dry run mode (do not submit)")
    parser.add_argument("--batch-size", type=int, default=10,
                        help="Batch size (default: 10)")
    parser.add_argument("--delay", type=float, default=0.1,
                        help="Delay between batches in seconds (default: 0.1)")

    args = parser.parse_args()

    # Validate input file
    if not os.path.exists(args.task_file):
        logger.error(f"Task file not found: {args.task_file}")
        sys.exit(1)

    # Create submitter
    submitter = APITaskSubmitter(args.api_url, args.task_file)

    try:
        submitter.run_submission(
            dry_run=args.dry_run,
            batch_size=args.batch_size,
            delay=args.delay
        )

        logger.info("\nSubmission completed")

        if submitter.stats['pending_verification'] > 0:
            logger.info(f"\n* Successfully triggered {submitter.stats['pending_verification']} verification tasks")
            logger.info("Verification consumers will process these tasks and may reuse bisect results.")

    except KeyboardInterrupt:
        logger.warning("\nSubmission interrupted by user")
    except Exception as e:
        logger.error(f"Submission failed: {str(e)}")
        logger.error(traceback.format_exc())
        sys.exit(1)


if __name__ == "__main__":
    main()
