#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Commit Time Query - query Git commit 

 SharedRepoManager  pristine repoquery commit ，
， pristine repo git log 。
"""

import os
import sys
import subprocess
import time
import re
import threading
from typing import Optional, Dict, Tuple, List, Any
from datetime import datetime, timezone
from contextlib import nullcontext

# 
lib_path = os.path.join(os.environ.get('CCI_SRC', '/srv/cci'), 'container/bisect/lib')
if lib_path not in sys.path:
    sys.path.insert(0, lib_path)

from repo_manager import SharedRepoManager
from bisect_utils import extract_repo_name_from_url
from log_config import logger


class CommitTimeQuery:
    """Commit query"""

    def __init__(self, repo_manager: SharedRepoManager = None):
        """
        initializequery

        Args:
            repo_manager: repoinstance， None createinstance
        """
        self.repo_manager = repo_manager or SharedRepoManager()
        # Use a dedicated pristine directory for commit-time queries to avoid
        # contention with bisect worker clones that use the default pristine pool.
        self.pristine_base_dir = os.environ.get(
            'BISECT_COMMIT_QUERY_PRISTINE_BASE_DIR',
            os.path.join(os.environ.get('WORK_DIR', '/tmp'), 'bisect_repos', 'pristine_query')
        )
        os.makedirs(self.pristine_base_dir, exist_ok=True)
        self._fetch_locks = {}
        self._fetch_locks_lock = threading.Lock()
        self._metrics_lock = threading.Lock()
        self._fetch_metrics = {
            'fetch_attempts': 0,
            'fetch_successes': 0,
            'fetch_failures': 0,
            'last_fetch_at': 0,
            'last_fetch_repo': '',
            'last_fetch_error': ''
        }
        logger.info(f"Commit query pristine root: {self.pristine_base_dir}")

    def get_commit_timestamp(self, git_url: str, commit_hash: str) -> Optional[int]:
        """
        get commit  Unix 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash（）

        Returns:
            Unix ，queryfailed None
        """
        repo_name = extract_repo_name_from_url(git_url)
        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        #  pristine repo（support bare repo）
        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            logger.info(f"Pristine repo not found, need to clone | repo: {repo_name}")
            #  repo_manager repo
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return None

        # query commit 
        try:
            result = subprocess.run(
                ['git', '-C', pristine_repo_dir, 'log', '-1', '--format=%ct', commit_hash],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                # commit not found， fetch 
                logger.warning(f"Commit not found, trying fetch | commit: {commit_hash[:12]} | error: {result.stderr.strip()}")
                self._fetch_pristine_repo(pristine_repo_dir, git_url)

                # query
                result = subprocess.run(
                    ['git', '-C', pristine_repo_dir, 'log', '-1', '--format=%ct', commit_hash],
                    capture_output=True,
                    text=True,
                    timeout=30
                )

                if result.returncode != 0:
                    logger.error(f"Commit still not found after fetch | commit: {commit_hash[:12]}")
                    return None

            timestamp = int(result.stdout.strip())
            return timestamp

        except subprocess.TimeoutExpired:
            logger.error(f"Query timed out | commit: {commit_hash[:12]}")
            return None
        except ValueError as e:
            logger.error(f"Invalid timestamp format | commit: {commit_hash[:12]} | output: {result.stdout}")
            return None
        except Exception as e:
            logger.error(f"Query failed | commit: {commit_hash[:12]} | error: {str(e)}")
            return None

    def get_commit_info(self, git_url: str, commit_hash: str) -> Optional[Dict]:
        """
        get commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash

        Returns:
             commit dict:
            {
                'commit': str,           #  hash
                'timestamp': int,        # Unix 
                'date': str,             # ISO 
                'age_days': int,         # 
                'author': str,           # 
                'subject': str           # submit（）
            }
        """
        repo_name = extract_repo_name_from_url(git_url)
        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        #  pristine repo（support bare repo）
        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return None

        # query commit 
        # : hash|timestamp|author|subject
        format_str = '%H|%ct|%an|%s'

        try:
            result = subprocess.run(
                ['git', '-C', pristine_repo_dir, 'log', '-1', f'--format={format_str}', commit_hash],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                #  fetch 
                logger.warning(f"Commit not found, trying fetch | commit: {commit_hash[:12]}")
                self._fetch_pristine_repo(pristine_repo_dir, git_url)

                result = subprocess.run(
                    ['git', '-C', pristine_repo_dir, 'log', '-1', f'--format={format_str}', commit_hash],
                    capture_output=True,
                    text=True,
                    timeout=30
                )

                if result.returncode != 0:
                    logger.error(f"Commit still not found after fetch | commit: {commit_hash[:12]}")
                    return None

            # 
            parts = result.stdout.strip().split('|', 3)
            if len(parts) != 4:
                logger.error(f"Invalid git log output | commit: {commit_hash[:12]} | output: {result.stdout}")
                return None

            full_hash, timestamp_str, author, subject = parts
            timestamp = int(timestamp_str)

            # 
            now = int(time.time())
            age_seconds = now - timestamp
            age_days = age_seconds // 86400

            return {
                'commit': full_hash,
                'timestamp': timestamp,
                'date': datetime.fromtimestamp(timestamp, timezone.utc).isoformat().replace('+00:00', 'Z'),
                'age_days': age_days,
                'author': author,
                'subject': subject[:200]  # 
            }

        except subprocess.TimeoutExpired:
            logger.error(f"Query timed out | commit: {commit_hash[:12]}")
            return None
        except Exception as e:
            logger.error(f"Query failed | commit: {commit_hash[:12]} | error: {str(e)}")
            return None

    def get_commit_age_days(self, git_url: str, commit_hash: str) -> Optional[int]:
        """
        get commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash

        Returns:
            ，queryfailed None
        """
        timestamp = self.get_commit_timestamp(git_url, commit_hash)
        if timestamp is None:
            return None

        now = int(time.time())
        age_seconds = now - timestamp
        return age_seconds // 86400

    def is_commit_too_old(self, git_url: str, commit_hash: str, max_age_days: int = 365) -> Tuple[bool, Optional[int]]:
        """
        check commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash
            max_age_days: （default365）

        Returns:
            (is_too_old, age_days)
            - is_too_old: True ，False ，None queryfailed
            - age_days: ，queryfailed None
        """
        age_days = self.get_commit_age_days(git_url, commit_hash)
        if age_days is None:
            return (None, None)

        is_too_old = age_days > max_age_days
        return (is_too_old, age_days)

    def get_commit_base_tag(self, git_url: str, commit_hash: str) -> Optional[str]:
        """
        get commit  tag（ commit ）

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash

        Returns:
             tag，queryfailed None
            : 'v6.6-rc3', 'v4.9.337', 'v5.10.100'
        """
        repo_name = extract_repo_name_from_url(git_url)
        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        # repo
        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return None

        try:
            #  git describe --tags --abbrev=0 get tag
            result = subprocess.run(
                ['git', '-C', pristine_repo_dir, 'describe', '--tags', '--abbrev=0', commit_hash],
                capture_output=True,
                text=True,
                timeout=60
            )

            if result.returncode != 0:
                #  fetch
                logger.warning(f"Tag not found, trying fetch | commit: {commit_hash[:12]}")
                self._fetch_pristine_repo(pristine_repo_dir, git_url)

                # 
                result = subprocess.run(
                    ['git', '-C', pristine_repo_dir, 'describe', '--tags', '--abbrev=0', commit_hash],
                    capture_output=True,
                    text=True,
                    timeout=60
                )

                if result.returncode != 0:
                    logger.warning(f"No tag found for commit | commit: {commit_hash[:12]} | error: {result.stderr.strip()}")
                    return None

            tag = result.stdout.strip()
            return tag if tag else None

        except subprocess.TimeoutExpired:
            logger.error(f"Tag query timed out | commit: {commit_hash[:12]}")
            return None
        except Exception as e:
            logger.error(f"Tag query failed | commit: {commit_hash[:12]} | error: {str(e)}")
            return None

    @staticmethod
    def parse_kernel_version(tag: str) -> Optional[Tuple[int, int, Optional[int]]]:
        """
         tag

        Args:
            tag:  tag， 'v6.6-rc3', 'v4.9.337', 'v5.10.100'

        Returns:
            (major, minor, patch) ，failed None
        """
        if not tag:
            return None

        #  Linux : v<major>.<minor>[.<patch>][-rc<n>]
        match = re.match(r'^v?(\d+)\.(\d+)(?:\.(\d+))?', tag)
        if match:
            major = int(match.group(1))
            minor = int(match.group(2))
            patch = int(match.group(3)) if match.group(3) else None
            return (major, minor, patch)

        return None

    @staticmethod
    def compare_kernel_versions(v1: Tuple[int, int, Optional[int]],
                                 v2: Tuple[int, int, Optional[int]]) -> int:
        """
        

        Returns:
            -1: v1 < v2, 0: v1 == v2, 1: v1 > v2
        """
        if v1[0] != v2[0]:
            return -1 if v1[0] < v2[0] else 1
        if v1[1] != v2[1]:
            return -1 if v1[1] < v2[1] else 1
        p1 = v1[2] if v1[2] is not None else 0
        p2 = v2[2] if v2[2] is not None else 0
        if p1 != p2:
            return -1 if p1 < p2 else 1
        return 0

    def is_commit_on_old_branch(self, git_url: str, commit_hash: str,
                                 min_version: str = "5.10") -> Tuple[Optional[bool], Optional[str], Optional[Tuple]]:
        """
        check commit （ base tag）

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash
            min_version: support， "5.10"  "6.1"

        Returns:
            (is_old_branch, base_tag, parsed_version)
        """
        min_parsed = self.parse_kernel_version(f"v{min_version}")
        if not min_parsed:
            logger.error(f"Invalid min_version format: {min_version}")
            return (None, None, None)

        base_tag = self.get_commit_base_tag(git_url, commit_hash)
        if not base_tag:
            return (None, None, None)

        tag_version = self.parse_kernel_version(base_tag)
        if not tag_version:
            logger.warning(f"Cannot parse tag version | tag: {base_tag}")
            return (None, base_tag, None)

        is_old = self.compare_kernel_versions(tag_version, min_parsed) < 0

        logger.debug(
            f"Version check | commit: {commit_hash[:12]} | "
            f"base_tag: {base_tag} | version: {tag_version} | "
            f"min_version: {min_parsed} | is_old: {is_old}"
        )

        return (is_old, base_tag, tag_version)

    def is_ancestor(self, git_url: str, ancestor_commit: str, descendant_commit: str) -> Optional[bool]:
        """
        Check if ancestor_commit is an ancestor of descendant_commit.

        Uses `git merge-base --is-ancestor` in the pristine repo.

        Args:
            git_url: Git repository URL
            ancestor_commit: The potential ancestor commit hash
            descendant_commit: The potential descendant commit hash

        Returns:
            True if confirmed ancestor, False if confirmed not ancestor,
            None if cannot determine (commit not in repo, timeout, error).
        """
        if not git_url or not ancestor_commit or not descendant_commit:
            return None

        repo_name = extract_repo_name_from_url(git_url)
        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return None

        try:
            result = subprocess.run(
                ['git', '-C', pristine_repo_dir, 'merge-base', '--is-ancestor',
                 ancestor_commit, descendant_commit],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0:
                return True
            elif result.returncode == 1:
                # returncode 1 = commits exist but not in ancestor relationship
                return False
            else:
                # returncode 128 or other = commit not found, try fetch and retry
                logger.warning(f"is_ancestor check error, trying fetch | ancestor: {ancestor_commit[:12]} | "
                              f"descendant: {descendant_commit[:12]} | stderr: {result.stderr.strip()}")
                self._fetch_pristine_repo(pristine_repo_dir, git_url)

                result = subprocess.run(
                    ['git', '-C', pristine_repo_dir, 'merge-base', '--is-ancestor',
                     ancestor_commit, descendant_commit],
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                if result.returncode == 0:
                    return True
                elif result.returncode == 1:
                    return False
                else:
                    logger.warning(f"is_ancestor still failed after fetch | "
                                  f"ancestor: {ancestor_commit[:12]} | descendant: {descendant_commit[:12]}")
                    return None  # Cannot determine — commit not in repo

        except subprocess.TimeoutExpired:
            logger.error(f"is_ancestor timed out | ancestor: {ancestor_commit[:12]} | "
                        f"descendant: {descendant_commit[:12]}")
            return None
        except Exception as e:
            logger.error(f"is_ancestor failed | ancestor: {ancestor_commit[:12]} | "
                        f"descendant: {descendant_commit[:12]} | error: {str(e)}")
            return None

    def _ensure_pristine_repo(self, git_url: str, pristine_repo_dir: str):
        """ pristine repo"""
        repo_key = self.repo_manager._canonical_repo_key(git_url)
        #  repo_manager  pristine 
        with self.repo_manager.pristine_locks_lock:
            if repo_key not in self.repo_manager.pristine_locks:
                import threading
                self.repo_manager.pristine_locks[repo_key] = threading.Lock()
            pristine_lock = self.repo_manager.pristine_locks[repo_key]

        with pristine_lock:
            with self._cross_process_lock(git_url, pristine_repo_dir):
                self.repo_manager._ensure_pristine_repo(git_url, pristine_repo_dir)

    def _cross_process_lock(self, git_url: Optional[str], pristine_repo_dir: str):
        """Best-effort cross-process lock if repo_manager exposes file-lock API."""
        if git_url:
            lock_fn = getattr(self.repo_manager, '_pristine_file_lock', None)
            if callable(lock_fn):
                try:
                    ctx = lock_fn(git_url, pristine_repo_dir)
                    if hasattr(ctx, '__enter__') and hasattr(ctx, '__exit__'):
                        return ctx
                except Exception:
                    pass
        return nullcontext()

    def _fetch_pristine_repo(self, pristine_repo_dir: str, git_url: Optional[str] = None) -> bool:
        """ pristine repo (per-repo lock to avoid concurrent fetches)"""
        with self._fetch_locks_lock:
            if pristine_repo_dir not in self._fetch_locks:
                self._fetch_locks[pristine_repo_dir] = threading.Lock()
            lock = self._fetch_locks[pristine_repo_dir]

        if not lock.acquire(blocking=False):
            logger.info(f"Fetch already in progress, waiting | path: {pristine_repo_dir}")
            lock.acquire()
            lock.release()
            return True

        try:
            with self._metrics_lock:
                self._fetch_metrics['fetch_attempts'] += 1
                self._fetch_metrics['last_fetch_at'] = int(time.time())
                self._fetch_metrics['last_fetch_repo'] = pristine_repo_dir
                self._fetch_metrics['last_fetch_error'] = ''

            with self._cross_process_lock(git_url, pristine_repo_dir):
                # Bare repos cloned long ago may miss remote.origin.fetch.
                # Ensure it exists so fetch pulls refs/tags for commit lookup.
                cfg = subprocess.run(
                    ['git', '-C', pristine_repo_dir, 'config', 'remote.origin.fetch'],
                    capture_output=True,
                    text=True,
                    timeout=15
                )
                if not (cfg.stdout or '').strip():
                    subprocess.run(
                        ['git', '-C', pristine_repo_dir, 'config', 'remote.origin.fetch', '+refs/*:refs/*'],
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=15
                    )
                result = subprocess.run(
                    ['git', '-C', pristine_repo_dir, 'fetch', 'origin'],
                    capture_output=True,
                    text=True,
                    timeout=120
                )
            if result.returncode != 0:
                with self._metrics_lock:
                    self._fetch_metrics['fetch_failures'] += 1
                    self._fetch_metrics['last_fetch_error'] = (result.stderr or '').strip()[:200]
                logger.warning(
                    f"Fetch failed | path: {pristine_repo_dir} | "
                    f"stderr: {(result.stderr or '').strip()[:200]}"
                )
                return False
            with self._metrics_lock:
                self._fetch_metrics['fetch_successes'] += 1
            logger.info(f"Pristine repo fetched | path: {pristine_repo_dir}")
            return True
        except Exception as e:
            with self._metrics_lock:
                self._fetch_metrics['fetch_failures'] += 1
                self._fetch_metrics['last_fetch_error'] = str(e)[:200]
            logger.warning(f"Fetch failed | path: {pristine_repo_dir} | error: {str(e)}")
            return False
        finally:
            lock.release()

    def get_metrics(self) -> Dict[str, Any]:
        """Return lightweight query/fetch metrics for health/stats endpoints."""
        with self._metrics_lock:
            fetch_metrics = dict(self._fetch_metrics)
        lock_metrics = {}
        if hasattr(self.repo_manager, 'get_pristine_lock_metrics'):
            try:
                lock_metrics = self.repo_manager.get_pristine_lock_metrics()
            except Exception:
                lock_metrics = {}
        return {
            'pristine_base_dir': self.pristine_base_dir,
            'fetch': fetch_metrics,
            'pristine_lock': lock_metrics
        }

    def _resolve_commitish(self, pristine_repo_dir: str, ref: str, timeout: int = 30) -> Optional[str]:
        """Resolve any commit-ish ref (sha, tag, branch) to a commit SHA."""
        result = subprocess.run(
            ['git', '-C', pristine_repo_dir, 'rev-parse', '--verify', '--quiet', f'{ref}^{{commit}}'],
            capture_output=True,
            text=True,
            timeout=timeout
        )
        if result.returncode != 0:
            return None
        resolved = result.stdout.strip()
        return resolved or None

    def get_parent_commit_detailed(self, git_url: str, commit_hash: str) -> Dict[str, Any]:
        """
        Get parent info with structured error semantics.

        Returns:
            {
                'status': 'success',
                'data': {...}
            }
            or
            {
                'status': 'error',
                'error_code': str,
                'error': str,
                'retryable': bool
            }
        """
        if not git_url or not commit_hash or not str(commit_hash).strip():
            logger.warning(f"Invalid parameters | git_url: {git_url} | commit: {commit_hash}")
            return {
                'status': 'error',
                'error_code': 'invalid_parameters',
                'error': 'Missing git_url or commit',
                'retryable': False
            }

        ref = str(commit_hash).strip()

        try:
            repo_name = extract_repo_name_from_url(git_url)
            if not repo_name:
                return {
                    'status': 'error',
                    'error_code': 'invalid_git_url',
                    'error': f'Cannot extract repo name from git_url: {git_url}',
                    'retryable': False
                }
        except Exception as e:
            return {
                'status': 'error',
                'error_code': 'invalid_git_url',
                'error': f'Invalid git_url: {str(e)}',
                'retryable': False
            }

        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            logger.info(f"Pristine repo not found, need to clone | repo: {repo_name}")
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return {
                    'status': 'error',
                    'error_code': 'ensure_pristine_failed',
                    'error': f'Failed to prepare repo: {str(e)}',
                    'retryable': True
                }

        try:
            resolved_commit = self._resolve_commitish(pristine_repo_dir, ref)
            if not resolved_commit:
                logger.warning(f"Commit/ref not found, trying fetch | ref: {ref[:24]}")
                self._fetch_pristine_repo(pristine_repo_dir, git_url)
                resolved_commit = self._resolve_commitish(pristine_repo_dir, ref)

            if not resolved_commit:
                return {
                    'status': 'error',
                    'error_code': 'commit_not_found',
                    'error': f'Commit/ref not found: {ref}',
                    'retryable': False
                }

            # rev-list --parents output: "<commit> <parent1> <parent2> ..."
            result = subprocess.run(
                ['git', '-C', pristine_repo_dir, 'rev-list', '--parents', '-n', '1', resolved_commit],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                logger.warning(
                    f"Parent query failed, trying fetch | commit: {resolved_commit[:12]} | "
                    f"stderr: {result.stderr.strip()}"
                )
                self._fetch_pristine_repo(pristine_repo_dir, git_url)
                result = subprocess.run(
                    ['git', '-C', pristine_repo_dir, 'rev-list', '--parents', '-n', '1', resolved_commit],
                    capture_output=True,
                    text=True,
                    timeout=30
                )

            if result.returncode != 0:
                stderr = (result.stderr or '').strip()
                error_code = 'git_query_failed'
                retryable = True
                if any(k in stderr.lower() for k in ['unknown revision', 'bad object', 'needed a single revision']):
                    error_code = 'commit_not_found'
                    retryable = False

                return {
                    'status': 'error',
                    'error_code': error_code,
                    'error': f'Parent query failed: {stderr or "unknown git error"}',
                    'retryable': retryable
                }

            tokens = [tok for tok in result.stdout.strip().split() if tok]
            if not tokens:
                return {
                    'status': 'error',
                    'error_code': 'git_query_failed',
                    'error': 'Empty git output while querying parent commit',
                    'retryable': True
                }

            parents = tokens[1:]
            response = {
                'commit': tokens[0],
                'parent': parents[0] if parents else None,
                'parent_count': len(parents)
            }
            if not parents:
                response['reason'] = 'root_commit'
            if tokens[0] != ref:
                response['input_ref'] = ref

            if len(parents) > 1:
                logger.debug(
                    f"Merge commit detected | commit: {tokens[0][:12]} | parents: {len(parents)}"
                )

            return {'status': 'success', 'data': response}

        except subprocess.TimeoutExpired:
            logger.error(f"Parent query timed out | commit: {ref[:12]}")
            return {
                'status': 'error',
                'error_code': 'git_timeout',
                'error': f'Git command timeout while querying parent for {ref}',
                'retryable': True
            }
        except Exception as e:
            logger.error(f"Parent query failed | commit: {ref[:12]} | error: {str(e)}")
            return {
                'status': 'error',
                'error_code': 'git_query_failed',
                'error': str(e),
                'retryable': True
            }

    def get_parent_commit(self, git_url: str, commit_hash: str) -> Optional[Dict]:
        """Backward-compatible wrapper that returns parent info dict or None."""
        result = self.get_parent_commit_detailed(git_url, commit_hash)
        if result.get('status') != 'success':
            return None
        return result.get('data')



# instance（service）
_query_instance = None


def get_query_instance() -> CommitTimeQuery:
    """getqueryinstance"""
    global _query_instance
    if _query_instance is None:
        _query_instance = CommitTimeQuery()
    return _query_instance


if __name__ == '__main__':
    # test
    print("test CommitTimeQuery...")
    print("=" * 60)

    # 
    if 'CCI_SRC' not in os.environ:
        os.environ['CCI_SRC'] = '/srv/cci'
    if 'WORK_DIR' not in os.environ:
        os.environ['WORK_DIR'] = '/tmp'
    if 'LKP_SRC' not in os.environ:
        os.environ['LKP_SRC'] = '/srv/lkp'

    query = CommitTimeQuery()

    # test
    test_url = 'https://gitee.com/openeuler/kernel.git'
    test_commit = '5e5d40e65cb55e4699c9879674a004f246606a8d'

    print(f"\ntestrepo: {test_url}")
    print(f"test commit: {test_commit}")

    # test 1: get
    print("\n--- test 1: get ---")
    timestamp = query.get_commit_timestamp(test_url, test_commit)
    if timestamp:
        print(f": {timestamp}")
        print(f": {datetime.utcfromtimestamp(timestamp).isoformat()}")
    else:
        print("queryfailed")

    # test 2: get
    print("\n--- test 2: get ---")
    info = query.get_commit_info(test_url, test_commit)
    if info:
        for key, value in info.items():
            print(f"  {key}: {value}")
    else:
        print("queryfailed")

    # test 3: check
    print("\n--- test 3: check 365  ---")
    is_old, age = query.is_commit_too_old(test_url, test_commit, max_age_days=365)
    if is_old is not None:
        print(f": {age} ")
        print(f"365: {'' if is_old else ''}")
    else:
        print("queryfailed")

    print("\n" + "=" * 60)
    print("testcompleted")
