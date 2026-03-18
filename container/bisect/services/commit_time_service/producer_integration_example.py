#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Bisect Producer Integration Example

 bisect_producer  commit 
"""

import os
import sys
import re

#  commit time service client 
sys.path.insert(0, os.path.join(os.environ.get('CCI_SRC', '/srv/cci'),
                                 'container/bisect/services/commit_time_service'))

from client import CommitTimeClient


def extract_commit_from_full_text_kv(full_text_kv: str) -> str:
    """
     full_text_kv  commit hash

    Args:
        full_text_kv: jobs  full_text_kv 

    Returns:
        Commit hash，
    """
    #  commit 
    patterns = [
        r'commit[:=]\s*([a-f0-9]{40})',          # commit: abc123...
        r'commit[:=]\s*([a-f0-9]{12,})',         # commit: abc123 (12+)
        r'head[:=]\s*([a-f0-9]{40})',            # head: abc123...
        r'HEAD[:=]\s*([a-f0-9]{40})',            # HEAD: abc123...
    ]

    for pattern in patterns:
        match = re.search(pattern, full_text_kv, re.IGNORECASE)
        if match:
            return match.group(1)

    return ''


class BisectProducerWithCommitFilter:
    """
     commit  Bisect Producer 

    ， ErrorBisectProducer
    """

    def __init__(self, client, config):
        """initialize"""
        self.client = client
        self.config = config

        # initialize commit time client
        commit_service_url = config.get(
            'commit_time_service_url',
            os.environ.get('COMMIT_TIME_SERVICE_URL', 'http://localhost:8765')
        )
        self.commit_client = CommitTimeClient(commit_service_url)

        # commit （）
        self.max_commit_age_days = config.get(
            'max_commit_age_days',
            int(os.environ.get('BISECT_MAX_COMMIT_AGE_DAYS', '365'))
        )

        # checkservice
        if self.commit_client.ping():
            print(f"Commit time service is available at {commit_service_url}")
        else:
            print(f"WARNING: Commit time service is NOT available at {commit_service_url}")
            print("Commit age filtering will be disabled (graceful degradation)")

    def should_filter_old_commit(self, git_url: str, full_text_kv: str) -> tuple:
        """
        check commit

        Args:
            git_url: Git repo URL
            full_text_kv: job full_text_kv

        Returns:
            (should_filter, reason)
            - should_filter: True 
            - reason: reason（log）
        """
        #  commit
        commit_hash = extract_commit_from_full_text_kv(full_text_kv)

        if not commit_hash:
            #  commit，（）
            return (False, 'no_commit_found')

        # check commit 
        is_old = self.commit_client.is_commit_too_old(
            git_url,
            commit_hash,
            max_age_days=self.max_commit_age_days
        )

        if is_old:
            return (True, f'commit_too_old (>{self.max_commit_age_days} days)')

        return (False, 'commit_age_ok')

    def execute_producer_cycle_example(self):
        """
        Producer （）

         execute_producer_cycle  commit 
        """
        stats = {
            'filtered_old_commits': 0,
            'commit_age_check_failed': 0,
        }

        # query jobs
        jobs = [
            {
                'id': 123456,
                'git_url': 'https://gitee.com/openeuler/kernel.git',
                'full_text_kv': 'commit: abc123def456...',
                'error_ids': ['error1', 'error2']
            }
        ]

        for job in jobs:
            git_url = job.get('git_url')
            full_text_kv = job.get('full_text_kv', '')

            if not git_url:
                continue

            # check commit 
            should_filter, reason = self.should_filter_old_commit(git_url, full_text_kv)

            if should_filter:
                stats['filtered_old_commits'] += 1
                print(f"Filtered old commit | job_id: {job['id']} | reason: {reason}")
                continue  # skip job

            # ... （create bisect task）

        print(f"\nstats:")
        print(f"   commit: {stats['filtered_old_commits']}")


def integration_example():
    """"""
    print("=" * 60)
    print("Bisect Producer Commit Age Filter Integration Example")
    print("=" * 60)

    # config
    config = {
        'commit_time_service_url': 'http://localhost:8765',
        'max_commit_age_days': 365
    }

    # create producer（）
    producer = BisectProducerWithCommitFilter(None, config)

    # test commit 
    print("\ntest commit :")
    print("-" * 60)

    test_cases = [
        {
            'git_url': 'https://gitee.com/openeuler/kernel.git',
            'full_text_kv': 'commit: 5e5d40e65cb55e4699c9879674a004f246606a8d',
            'desc': ' commit'
        },
        {
            'git_url': 'https://gitee.com/openeuler/kernel.git',
            'full_text_kv': 'no commit here',
            'desc': ' commit '
        }
    ]

    for test in test_cases:
        should_filter, reason = producer.should_filter_old_commit(
            test['git_url'],
            test['full_text_kv']
        )
        print(f"{test['desc']}:")
        print(f"  : {should_filter} | reason: {reason}")

    print("\n" + "=" * 60)


if __name__ == '__main__':
    integration_example()
