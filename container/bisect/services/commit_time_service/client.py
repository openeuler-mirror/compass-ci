#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Commit Time Service Client

 bisect_producer 
"""

import requests
from typing import Optional, Dict, Tuple, List, Set


class CommitTimeClient:
    """Commit service"""

    def __init__(self, service_url: str = 'http://localhost:8765', timeout: int = 120):
        """
        initialize

        Args:
            service_url: service
            timeout: timeout（）
        """
        self.service_url = service_url.rstrip('/')
        self.timeout = timeout

    def get_commit_info(self, git_url: str, commit_hash: str) -> Optional[Dict]:
        """
        get commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash

        Returns:
            Commit dict，queryfailed None
        """
        try:
            response = requests.get(
                f"{self.service_url}/api/v1/commit/time",
                params={'repo': git_url, 'commit': commit_hash},
                timeout=self.timeout
            )

            if response.status_code == 200:
                result = response.json()
                if result['status'] == 'success':
                    return result['data']

            return None

        except Exception as e:
            # failed， None
            return None

    def check_commit_age(self, git_url: str, commit_hash: str,
                        max_age_days: int = 365) -> Tuple[Optional[bool], Optional[int]]:
        """
        check commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash
            max_age_days: 

        Returns:
            (is_too_old, age_days)
            - is_too_old: True ，None queryfailed
            - age_days: ，queryfailed None
        """
        try:
            response = requests.get(
                f"{self.service_url}/api/v1/commit/check",
                params={
                    'repo': git_url,
                    'commit': commit_hash,
                    'max_age_days': max_age_days
                },
                timeout=self.timeout
            )

            if response.status_code == 200:
                result = response.json()
                if result['status'] == 'success':
                    return (result['data']['is_too_old'], result['data']['age_days'])

            return (None, None)

        except Exception as e:
            # failed
            return (None, None)

    def is_commit_too_old(self, git_url: str, commit_hash: str,
                          max_age_days: int = 365) -> bool:
        """
        check：commit （ producer ）

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash
            max_age_days: 

        Returns:
            True: commit 
            False: commit queryfailed（）
        """
        is_old, age = self.check_commit_age(git_url, commit_hash, max_age_days)

        # ：queryfailed
        if is_old is None:
            return False

        return is_old

    def batch_check_commits(self, items: List[Dict], max_age_days: int = 365,
                             min_kernel_version: str = None) -> Tuple[Set[str], Set[str]]:
        """
        check commit 

        Args:
            items: list， {'job_id': ..., 'git_url': ..., 'commit': ...}
            max_age_days: 
            min_kernel_version: （ "5.10"）， None check

        Returns:
            (too_old_job_ids, valid_job_ids) 
            - too_old_job_ids:  job_id （）
            - valid_job_ids:  job_id 
        """
        if not items:
            return set(), set()

        try:
            request_body = {
                'items': items,
                'max_age_days': max_age_days
            }
            if min_kernel_version:
                request_body['min_kernel_version'] = min_kernel_version

            response = requests.post(
                f"{self.service_url}/api/v1/commit/batch_check",
                json=request_body,
                timeout=self.timeout * 2  # timeout
            )

            if response.status_code == 200:
                result = response.json()
                if result.get('status') == 'success':
                    data = result['data']
                    return (
                        set(data.get('too_old_job_ids', [])),
                        set(data.get('valid_job_ids', []))
                    )

            # failed，：
            return set(), set(item['job_id'] for item in items if item.get('job_id'))

        except Exception as e:
            # exception：
            return set(), set(item['job_id'] for item in items if item.get('job_id'))

    def check_branch_version(self, git_url: str, commit_hash: str,
                              min_version: str = "5.10") -> Tuple[Optional[bool], Optional[str]]:
        """
        check commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash
            min_version: support

        Returns:
            (is_old_branch, base_tag)
            - is_old_branch: True ，None 
            - base_tag:  tag 
        """
        try:
            response = requests.get(
                f"{self.service_url}/api/v1/commit/branch_check",
                params={
                    'repo': git_url,
                    'commit': commit_hash,
                    'min_version': min_version
                },
                timeout=self.timeout
            )

            if response.status_code == 200:
                result = response.json()
                if result['status'] == 'success':
                    data = result['data']
                    return (data['is_old_branch'], data['base_tag'])

            return (None, None)

        except Exception as e:
            return (None, None)

    def is_ancestor(self, git_url: str, ancestor_commit: str,
                    descendant_commit: str) -> Optional[bool]:
        """
        Check if ancestor_commit is an ancestor of descendant_commit.

        Args:
            git_url: Git repository URL
            ancestor_commit: The potential ancestor commit hash
            descendant_commit: The potential descendant commit hash

        Returns:
            True if ancestor, False if not, None if query failed
        """
        try:
            response = requests.get(
                f"{self.service_url}/api/v1/commit/is-ancestor",
                params={
                    'repo': git_url,
                    'ancestor': ancestor_commit,
                    'descendant': descendant_commit
                },
                timeout=self.timeout
            )

            if response.status_code == 200:
                result = response.json()
                if result.get('status') == 'success':
                    return result['data']['is_ancestor']

            return None

        except Exception:
            return None

    def batch_is_ancestor(self, git_url: str,
                          pairs: List[Tuple[str, str]]) -> List[Optional[bool]]:
        """
        Batch check ancestry via server-side parallel endpoint.

        Args:
            git_url: Git repository URL
            pairs: List of (ancestor_commit, descendant_commit) tuples

        Returns:
            List of results: True/False/None per pair, same order as input
        """
        if not pairs:
            return []

        try:
            request_body = {
                'git_url': git_url,
                'pairs': [
                    {'ancestor': anc, 'descendant': desc}
                    for anc, desc in pairs
                ]
            }

            response = requests.post(
                f"{self.service_url}/api/v1/commit/batch_is_ancestor",
                json=request_body,
                timeout=self.timeout * 2
            )

            if response.status_code == 200:
                result = response.json()
                if result.get('status') == 'success':
                    return [
                        r.get('is_ancestor')
                        for r in result['data']['results']
                    ]

            return [None] * len(pairs)

        except Exception:
            return [None] * len(pairs)

    def batch_check_ancestry(self, git_url: str,
                             pairs: List[Tuple[str, str]]) -> Set[int]:
        """
        Batch check ancestry for multiple commit pairs.

        Uses server-side batch endpoint for parallel execution.

        Args:
            git_url: Git repository URL
            pairs: List of (ancestor_commit, descendant_commit) tuples

        Returns:
            Set of indices of pairs that are NOT in an ancestor relationship
        """
        if not pairs:
            return set()

        results = self.batch_is_ancestor(git_url, pairs)

        invalid_indices = set()
        for i, result in enumerate(results):
            if result is False:
                invalid_indices.add(i)
            # None (error) → skip, graceful degradation

        return invalid_indices

    def get_parent_commit(self, git_url: str, commit: str) -> Optional[str]:
        """
        get commit submit hash

        Args:
            git_url: Git repo URL
            commit: Commit hash（）

        Returns:
            submit hash（40 ）
            -  root commit  None
            - queryfailed None
        """
        try:
            response = requests.get(
                f"{self.service_url}/api/v1/commit/parent",
                params={'repo': git_url, 'commit': commit},
                timeout=self.timeout
            )

            if response.status_code == 200:
                result = response.json()
                if result.get('status') == 'success':
                    data = result['data']
                    #  parent hash（root commit  None）
                    return data.get('parent')
                else:
                    # service error status
                    import logging
                    logger = logging.getLogger(__name__)
                    logger.warning(f"get_parent_commit API error | commit: {commit[:12]} | "
                                  f"error: {result.get('error', 'unknown')}")

            return None

        except Exception as e:
            # service None
            import logging
            logger = logging.getLogger(__name__)
            logger.warning(f"get_parent_commit request failed | commit: {commit[:12]} | error: {str(e)}")
            return None

    def get_parent_commit_info(self, git_url: str, commit: str) -> Optional[Dict]:
        """
        get commit submit

        Args:
            git_url: Git repo URL
            commit: Commit hash

        Returns:
            submitdict：
            {
                'commit': str,        #  commit hash
                'parent': str | None, # submit hash
                'parent_count': int,  # submitcount
                'reason': str         #  root_commit 
            }
            queryfailed None
        """
        try:
            response = requests.get(
                f"{self.service_url}/api/v1/commit/parent",
                params={'repo': git_url, 'commit': commit},
                timeout=self.timeout
            )

            if response.status_code == 200:
                result = response.json()
                if result.get('status') == 'success':
                    return result['data']

            return None

        except Exception:
            return None

    def ping(self) -> bool:
        """
        checkservice

        Returns:
            True: service
            False: service
        """
        try:
            response = requests.get(
                f"{self.service_url}/health",
                timeout=self.timeout
            )
            return response.status_code == 200
        except requests.RequestException:
            return False


if __name__ == '__main__':
    # 
    client = CommitTimeClient('http://localhost:8765')

    # testservice
    if client.ping():
        print("Service is healthy")
    else:
        print("Service is not available")

    # get commit 
    info = client.get_commit_info(
        'https://gitee.com/openeuler/kernel.git',
        '5e5d40e65cb55e4699c9879674a004f246606a8d'
    )
    if info:
        print(f"Commit: {info['commit']}")
        print(f"Age: {info['age_days']} days")
        print(f"Author: {info['author']}")

    # check
    is_old = client.is_commit_too_old(
        'https://gitee.com/openeuler/kernel.git',
        '5e5d40e65cb55e4699c9879674a004f246606a8d',
        max_age_days=365
    )
    print(f"Is too old: {is_old}")
