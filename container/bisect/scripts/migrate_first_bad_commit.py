#!/usr/bin/env python3
"""
Data migration script: separate first_bad_commit field

Separate first_bad_commit containing "SHA + subject" into:
- first_bad_commit: pure SHA (40 characters)
- j.first_bad_commit_subject: commit subject
- j.change_point: SHA + subject (for display)

Usage:
    # Check tasks needing migration (dry-run)
    python3 migrate_first_bad_commit.py --dry-run

    # Execute migration
    python3 migrate_first_bad_commit.py

    # Migrate a specific number of tasks
    python3 migrate_first_bad_commit.py --limit 100

    # Use a specific ManticoreSearch host
    python3 migrate_first_bad_commit.py --host localhost:9308
"""

import os
import sys
import re
import json
import time
import argparse
from typing import Dict, List, Tuple, Optional

# Add project path
sys.path.append(os.environ.get('CCI_SRC', '/srv/cci') + '/container/bisect/lib')
sys.path.append(os.environ.get('LKP_SRC', '/srv/lkp') + '/sbin/bisect/')

from log_config import logger
from lkp_bisect.db.manticore import ManticoreClient


class FirstBadCommitMigrator:
    """first_bad_commit field migrator"""

    def __init__(self, host: str = None, dry_run: bool = False):
        """
        Initialize migrator

        Args:
            host: ManticoreSearch host address
            dry_run: check only without modifying
        """
        self.dry_run = dry_run
        self.client = ManticoreClient(host or os.environ.get('MANTICORE_HOST', 'localhost:9308'))

        # Statistics
        self.stats = {
            'total_checked': 0,
            'need_migration': 0,
            'already_migrated': 0,
            'migrated': 0,
            'failed': 0,
            'skipped': 0
        }

    def is_commit_hash(self, text: str) -> bool:
        """
        Check if the text is a valid git commit hash (40 hex characters)

        Args:
            text: text to check

        Returns:
            bool: whether it is a valid commit hash
        """
        if not text or len(text) != 40:
            return False
        return bool(re.match(r'^[a-f0-9]{40}$', text, re.IGNORECASE))

    def parse_first_bad_commit(self, first_bad_commit: str) -> Tuple[Optional[str], Optional[str]]:
        """
        Parse first_bad_commit field, separate SHA and subject

        Args:
            first_bad_commit: original field value

        Returns:
            (sha, subject): separated SHA and subject, returns (None, None) if cannot parse
        """
        if not first_bad_commit or not isinstance(first_bad_commit, str):
            return None, None

        # If length is exactly 40, it may be a pure SHA (already migrated)
        if len(first_bad_commit) == 40:
            if self.is_commit_hash(first_bad_commit):
                return first_bad_commit, ""
            else:
                # Not a valid hash, possibly abnormal data
                return None, None

        # If length < 40, it is definitely not a complete commit hash
        if len(first_bad_commit) < 40:
            return None, None

        # Try to extract the first 40 characters as SHA
        potential_sha = first_bad_commit[:40]
        if not self.is_commit_hash(potential_sha):
            return None, None

        # Extract subject (skip spaces after SHA)
        remaining = first_bad_commit[40:].strip()

        return potential_sha, remaining

    def check_task_needs_migration(self, task: Dict) -> Tuple[bool, str]:
        """
        Check if task needs migration

        Args:
            task: task data

        Returns:
            (needs_migration, reason): whether migration is needed and reason
        """
        task_id = task.get('id')
        first_bad_commit = task.get('first_bad_commit', '')

        # Parse j field
        j_field = task.get('j', {})
        if isinstance(j_field, str):
            try:
                j_field = json.loads(j_field) if j_field else {}
            except json.JSONDecodeError:
                j_field = {}

        # Check if already migrated (has change_point field)
        if j_field.get('change_point'):
            return False, "already has change_point field"

        # Check if already migrated (has first_bad_commit_subject field)
        if j_field.get('first_bad_commit_subject') is not None:
            return False, "already has first_bad_commit_subject field"

        # Try to parse first_bad_commit
        sha, subject = self.parse_first_bad_commit(first_bad_commit)

        if sha is None:
            return False, f"cannot parse first_bad_commit (length: {len(first_bad_commit) if first_bad_commit else 0})"

        # If only SHA without subject, also needs migration (add empty subject field)
        if not subject:
            return True, "pure SHA, need to add subject field"

        # Has subject, needs migration
        return True, f"need to separate (SHA + subject length: {len(first_bad_commit)})"

    def migrate_task(self, task: Dict) -> bool:
        """
        Migrate a single task

        Args:
            task: task data

        Returns:
            bool: whether successful
        """
        task_id = task.get('id')
        first_bad_commit = task.get('first_bad_commit', '')

        try:
            # Parse
            sha, subject = self.parse_first_bad_commit(first_bad_commit)

            if sha is None:
                logger.error(f"Task {task_id} cannot parse first_bad_commit: {first_bad_commit}")
                return False

            # Construct change_point (for display)
            if subject:
                change_point = f"{sha} {subject}"
            else:
                change_point = sha

            # Parse j 
            j_field = task.get('j', {})
            if isinstance(j_field, str):
                try:
                    j_field = json.loads(j_field) if j_field else {}
                except json.JSONDecodeError:
                    j_field = {}
            elif not isinstance(j_field, dict):
                j_field = {}

            # Update j field
            j_field['first_bad_commit_subject'] = subject
            j_field['change_point'] = change_point
            j_field['_migrated_at'] = int(time.time())
            j_field['_migration_source'] = 'migrate_first_bad_commit.py'

            # Prepare update document
            update_doc = {
                "first_bad_commit": sha,  # Update to pure SHA
                "updated_at": int(time.time()),
                "j": j_field
            }

            if self.dry_run:
                logger.info(
                    f"[DRY-RUN] Task {task_id}:\n"
                    f"  Original: {first_bad_commit}\n"
                    f"  SHA: {sha}\n"
                    f"  Subject: {subject}\n"
                    f"  Change Point: {change_point}"
                )
                return True

            # Execute update
            result = self.client.update("bisect", task_id, update_doc)

            if result:
                logger.info(
                    f"Task {task_id} migrated successfully\n"
                    f"  SHA: {sha}\n"
                    f"  Subject: {subject[:50]}{'...' if len(subject) > 50 else ''}"
                )
                return True
            else:
                logger.error(f"Task {task_id} update failed")
                return False

        except Exception as e:
            logger.error(f"Task {task_id} migration error: {str(e)}")
            return False

    def scan_and_migrate(self, limit: int = None, batch_size: int = 100):
        """
        Scan and migrate tasks that need migration

        Args:
            limit: maximum number of tasks to migrate (None means all)
            batch_size: number of tasks per batch query
        """
        logger.info("=" * 80)
        logger.info("Starting scan for tasks needing migration...")
        logger.info(f"Mode: {'DRY-RUN (check only)' if self.dry_run else 'actual migration'}")
        if limit:
            logger.info(f"Limit: max {limit} tasks")
        logger.info("=" * 80)

        offset = 0
        migrated_count = 0

        while True:
            # Query tasks with success status
            query = f"""
                SELECT id, first_bad_commit, j
                FROM bisect
                WHERE bisect_status = 'success'
                ORDER BY id DESC
                LIMIT {batch_size}
                OFFSET {offset}
            """

            tasks = self.client.sql_select(query)

            if not tasks:
                logger.info("No more tasks")
                break

            logger.info(f"\nProcessing batch {offset // batch_size + 1}: {len(tasks)} tasks")

            for task in tasks:
                self.stats['total_checked'] += 1

                # Check if migration is needed
                needs_migration, reason = self.check_task_needs_migration(task)

                if not needs_migration:
                    self.stats['already_migrated'] += 1
                    logger.debug(f"Skipping task {task.get('id')}: {reason}")
                    continue

                self.stats['need_migration'] += 1
                logger.info(f"Task {task.get('id')}: {reason}")

                # Check if limit reached
                if limit and migrated_count >= limit:
                    logger.info(f"\nMigration limit reached ({limit}), stopping")
                    self.print_stats()
                    return

                # Execute migration
                if self.migrate_task(task):
                    self.stats['migrated'] += 1
                    migrated_count += 1
                else:
                    self.stats['failed'] += 1

            offset += batch_size

            # Print progress
            if offset % (batch_size * 10) == 0:
                logger.info(f"\nProgress: checked {self.stats['total_checked']} tasks, migrated {self.stats['migrated']}")

        logger.info("\nScan complete")
        self.print_stats()

    def print_stats(self):
        """Print statistics"""
        logger.info("\n" + "=" * 80)
        logger.info("Migration Statistics")
        logger.info("=" * 80)
        logger.info(f"Total checked:        {self.stats['total_checked']}")
        logger.info(f"Already migrated:     {self.stats['already_migrated']}")
        logger.info(f"Need migration:       {self.stats['need_migration']}")
        logger.info(f"Successfully migrated:{self.stats['migrated']}")
        logger.info(f"Failed:               {self.stats['failed']}")
        logger.info("=" * 80)

        if self.dry_run:
            logger.info("\nThis is DRY-RUN mode, no data was modified")
            logger.info("To execute migration, run: python3 migrate_first_bad_commit.py")


def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description='Migrate first_bad_commit field, separate SHA and subject',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Check tasks needing migration (no data modification)
  python3 migrate_first_bad_commit.py --dry-run

  # Execute migration（task）
  python3 migrate_first_bad_commit.py

  # Migrate first 100 tasks
  python3 migrate_first_bad_commit.py --limit 100

  # Specify ManticoreSearch host
  python3 migrate_first_bad_commit.py --host localhost:9308
        """
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Check only without modifying data'
    )

    parser.add_argument(
        '--limit',
        type=int,
        help='Maximum number of tasks to migrate'
    )

    parser.add_argument(
        '--host',
        type=str,
        help='ManticoreSearch host address (default: localhost:9308)'
    )

    parser.add_argument(
        '--batch-size',
        type=int,
        default=100,
        help='Number of tasks per batch query (default: 100)'
    )

    args = parser.parse_args()

    # Create migrator
    migrator = FirstBadCommitMigrator(
        host=args.host,
        dry_run=args.dry_run
    )

    # Execute migration
    try:
        migrator.scan_and_migrate(
            limit=args.limit,
            batch_size=args.batch_size
        )
    except KeyboardInterrupt:
        logger.info("\n\nMigration interrupted by user")
        migrator.print_stats()
        sys.exit(1)
    except Exception as e:
        logger.error(f"\nMigration process error: {str(e)}")
        import traceback
        traceback.print_exc()
        migrator.print_stats()
        sys.exit(1)


if __name__ == '__main__':
    main()
