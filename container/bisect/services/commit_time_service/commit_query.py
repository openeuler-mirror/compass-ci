#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Commit Time Query - 查询 Git commit 时间

复用 SharedRepoManager 的 pristine 仓库来查询 commit 信息，
无需额外克隆，直接在 pristine 仓库中执行 git log 命令。
"""

import os
import sys
import subprocess
import time
import re
import threading
from typing import Optional, Dict, Tuple, List
from datetime import datetime

# 添加项目路径
lib_path = os.path.join(os.environ.get('CCI_SRC', '/srv/cci'), 'container/bisect/lib')
if lib_path not in sys.path:
    sys.path.insert(0, lib_path)

from repo_manager import SharedRepoManager
from bisect_utils import extract_repo_name_from_url
from log_config import logger


class CommitTimeQuery:
    """Commit 时间查询器"""

    def __init__(self, repo_manager: SharedRepoManager = None):
        """
        初始化查询器

        Args:
            repo_manager: 共享仓库管理器实例，如果为 None 则创建新实例
        """
        self.repo_manager = repo_manager or SharedRepoManager()
        self.pristine_base_dir = self.repo_manager.PRISTINE_BASE_DIR
        self._fetch_locks = {}
        self._fetch_locks_lock = threading.Lock()

    def get_commit_timestamp(self, git_url: str, commit_hash: str) -> Optional[int]:
        """
        获取 commit 的 Unix 时间戳

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash（完整或简短）

        Returns:
            Unix 时间戳，如果查询失败返回 None
        """
        repo_name = extract_repo_name_from_url(git_url)
        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        # 确保 pristine 仓库存在（支持 bare 仓库）
        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            logger.info(f"Pristine repo not found, need to clone | repo: {repo_name}")
            # 使用 repo_manager 的方法确保仓库存在
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return None

        # 查询 commit 时间戳
        try:
            result = subprocess.run(
                ['git', '-C', pristine_repo_dir, 'log', '-1', '--format=%ct', commit_hash],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                # commit 可能不存在，尝试 fetch 更新
                logger.warning(f"Commit not found, trying fetch | commit: {commit_hash[:12]} | error: {result.stderr.strip()}")
                self._fetch_pristine_repo(pristine_repo_dir)

                # 重试查询
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
        获取 commit 的详细信息

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash

        Returns:
            包含 commit 信息的字典:
            {
                'commit': str,           # 完整 hash
                'timestamp': int,        # Unix 时间戳
                'date': str,             # ISO 格式日期
                'age_days': int,         # 距今天数
                'author': str,           # 作者
                'subject': str           # 提交信息（第一行）
            }
        """
        repo_name = extract_repo_name_from_url(git_url)
        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        # 确保 pristine 仓库存在（支持 bare 仓库）
        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return None

        # 查询 commit 详细信息
        # 格式: hash|timestamp|author|subject
        format_str = '%H|%ct|%an|%s'

        try:
            result = subprocess.run(
                ['git', '-C', pristine_repo_dir, 'log', '-1', f'--format={format_str}', commit_hash],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                # 尝试 fetch 更新
                logger.warning(f"Commit not found, trying fetch | commit: {commit_hash[:12]}")
                self._fetch_pristine_repo(pristine_repo_dir)

                result = subprocess.run(
                    ['git', '-C', pristine_repo_dir, 'log', '-1', f'--format={format_str}', commit_hash],
                    capture_output=True,
                    text=True,
                    timeout=30
                )

                if result.returncode != 0:
                    logger.error(f"Commit still not found after fetch | commit: {commit_hash[:12]}")
                    return None

            # 解析输出
            parts = result.stdout.strip().split('|', 3)
            if len(parts) != 4:
                logger.error(f"Invalid git log output | commit: {commit_hash[:12]} | output: {result.stdout}")
                return None

            full_hash, timestamp_str, author, subject = parts
            timestamp = int(timestamp_str)

            # 计算距今天数
            now = int(time.time())
            age_seconds = now - timestamp
            age_days = age_seconds // 86400

            return {
                'commit': full_hash,
                'timestamp': timestamp,
                'date': datetime.utcfromtimestamp(timestamp).isoformat() + 'Z',
                'age_days': age_days,
                'author': author,
                'subject': subject[:200]  # 限制长度
            }

        except subprocess.TimeoutExpired:
            logger.error(f"Query timed out | commit: {commit_hash[:12]}")
            return None
        except Exception as e:
            logger.error(f"Query failed | commit: {commit_hash[:12]} | error: {str(e)}")
            return None

    def get_commit_age_days(self, git_url: str, commit_hash: str) -> Optional[int]:
        """
        获取 commit 距今的天数

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash

        Returns:
            距今天数，如果查询失败返回 None
        """
        timestamp = self.get_commit_timestamp(git_url, commit_hash)
        if timestamp is None:
            return None

        now = int(time.time())
        age_seconds = now - timestamp
        return age_seconds // 86400

    def is_commit_too_old(self, git_url: str, commit_hash: str, max_age_days: int = 365) -> Tuple[bool, Optional[int]]:
        """
        检查 commit 是否超过指定天数

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash
            max_age_days: 最大天数阈值（默认365天）

        Returns:
            (is_too_old, age_days)
            - is_too_old: True 表示超过阈值，False 表示未超过，None 表示查询失败
            - age_days: 实际天数，查询失败时为 None
        """
        age_days = self.get_commit_age_days(git_url, commit_hash)
        if age_days is None:
            return (None, None)

        is_too_old = age_days > max_age_days
        return (is_too_old, age_days)

    def get_commit_base_tag(self, git_url: str, commit_hash: str) -> Optional[str]:
        """
        获取 commit 最近的祖先 tag（用于判断 commit 所在的分支版本）

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash

        Returns:
            最近的祖先 tag，如果查询失败返回 None
            例如: 'v6.6-rc3', 'v4.9.337', 'v5.10.100'
        """
        repo_name = extract_repo_name_from_url(git_url)
        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        # 确保仓库存在
        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return None

        try:
            # 使用 git describe --tags --abbrev=0 获取最近的祖先 tag
            result = subprocess.run(
                ['git', '-C', pristine_repo_dir, 'describe', '--tags', '--abbrev=0', commit_hash],
                capture_output=True,
                text=True,
                timeout=60
            )

            if result.returncode != 0:
                # 可能需要 fetch
                logger.warning(f"Tag not found, trying fetch | commit: {commit_hash[:12]}")
                self._fetch_pristine_repo(pristine_repo_dir)

                # 重试
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
        解析内核版本 tag

        Args:
            tag: 版本 tag，例如 'v6.6-rc3', 'v4.9.337', 'v5.10.100'

        Returns:
            (major, minor, patch) 元组，解析失败返回 None
        """
        if not tag:
            return None

        # 匹配标准 Linux 内核版本格式: v<major>.<minor>[.<patch>][-rc<n>]
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
        比较两个内核版本

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
        检查 commit 是否在旧版本分支上（基于 base tag）

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash
            min_version: 最小支持版本，例如 "5.10" 或 "6.1"

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

    def is_ancestor(self, git_url: str, ancestor_commit: str, descendant_commit: str) -> bool:
        """
        Check if ancestor_commit is an ancestor of descendant_commit.

        Uses `git merge-base --is-ancestor` in the pristine repo.

        Args:
            git_url: Git repository URL
            ancestor_commit: The potential ancestor commit hash
            descendant_commit: The potential descendant commit hash

        Returns:
            True if ancestor_commit is an ancestor of descendant_commit, False otherwise.
            Returns False on any error (graceful degradation).
        """
        if not git_url or not ancestor_commit or not descendant_commit:
            return False

        repo_name = extract_repo_name_from_url(git_url)
        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return False

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
                self._fetch_pristine_repo(pristine_repo_dir)

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
                    return False

        except subprocess.TimeoutExpired:
            logger.error(f"is_ancestor timed out | ancestor: {ancestor_commit[:12]} | "
                        f"descendant: {descendant_commit[:12]}")
            return False
        except Exception as e:
            logger.error(f"is_ancestor failed | ancestor: {ancestor_commit[:12]} | "
                        f"descendant: {descendant_commit[:12]} | error: {str(e)}")
            return False

    def _ensure_pristine_repo(self, git_url: str, pristine_repo_dir: str):
        """确保 pristine 仓库存在"""
        # 复用 repo_manager 的 pristine 锁机制
        with self.repo_manager.pristine_locks_lock:
            if git_url not in self.repo_manager.pristine_locks:
                import threading
                self.repo_manager.pristine_locks[git_url] = threading.Lock()
            pristine_lock = self.repo_manager.pristine_locks[git_url]

        with pristine_lock:
            self.repo_manager._ensure_pristine_repo(git_url, pristine_repo_dir)

    def _fetch_pristine_repo(self, pristine_repo_dir: str):
        """更新 pristine 仓库 (per-repo lock to avoid concurrent fetches)"""
        with self._fetch_locks_lock:
            if pristine_repo_dir not in self._fetch_locks:
                self._fetch_locks[pristine_repo_dir] = threading.Lock()
            lock = self._fetch_locks[pristine_repo_dir]

        if not lock.acquire(blocking=False):
            logger.info(f"Fetch already in progress, waiting | path: {pristine_repo_dir}")
            lock.acquire()
            lock.release()
            return

        try:
            subprocess.run(
                ['git', '-C', pristine_repo_dir, 'fetch', 'origin'],
                capture_output=True,
                text=True,
                timeout=120
            )
            logger.info(f"Pristine repo fetched | path: {pristine_repo_dir}")
        except Exception as e:
            logger.warning(f"Fetch failed | path: {pristine_repo_dir} | error: {str(e)}")
        finally:
            lock.release()

    def get_parent_commit(self, git_url: str, commit_hash: str) -> Optional[Dict]:
        """
        获取 commit 的父提交信息

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash（完整或简短）

        Returns:
            包含父提交信息的字典:
            {
                'commit': str,        # 原始 commit hash
                'parent': str | None, # 父提交 hash（root commit 为 None）
                'parent_count': int,  # 父提交数量（0=root, 1=普通, 2+=merge）
                'reason': str         # 仅在特殊情况下返回（如 'root_commit'）
            }
            查询失败返回 None
        """
        # 参数验证
        if not git_url or not commit_hash or not commit_hash.strip():
            logger.warning(f"Invalid parameters | git_url: {git_url} | commit: {commit_hash}")
            return None

        commit_hash = commit_hash.strip()

        # 获取仓库名和路径
        try:
            repo_name = extract_repo_name_from_url(git_url)
            if not repo_name:
                logger.warning(f"Cannot extract repo name | git_url: {git_url}")
                return None
        except Exception as e:
            logger.warning(f"Invalid git_url | git_url: {git_url} | error: {str(e)}")
            return None

        pristine_repo_dir = os.path.join(self.pristine_base_dir, repo_name)

        # 确保 pristine 仓库存在
        if not SharedRepoManager._is_git_repo(pristine_repo_dir):
            logger.info(f"Pristine repo not found, need to clone | repo: {repo_name}")
            try:
                self._ensure_pristine_repo(git_url, pristine_repo_dir)
            except Exception as e:
                logger.error(f"Failed to ensure pristine repo | repo: {repo_name} | error: {str(e)}")
                return None

        # 查询父提交
        try:
            # 首先获取父提交列表（支持 merge commit）
            result = subprocess.run(
                ['git', '-C', pristine_repo_dir, 'rev-parse', f'{commit_hash}^@'],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                # 可能是 commit 不存在或者是 root commit
                stderr = result.stderr.strip()

                # 检查是否是 root commit（没有 ^@ 语法的结果）
                # 尝试用 ^1 来确认
                check_result = subprocess.run(
                    ['git', '-C', pristine_repo_dir, 'rev-parse', f'{commit_hash}^1'],
                    capture_output=True,
                    text=True,
                    timeout=30
                )

                if check_result.returncode != 0:
                    # 可能是 commit 不存在，尝试 fetch
                    logger.warning(f"Parent not found, trying fetch | commit: {commit_hash[:12]}")
                    self._fetch_pristine_repo(pristine_repo_dir)

                    # 重试
                    check_result = subprocess.run(
                        ['git', '-C', pristine_repo_dir, 'rev-parse', f'{commit_hash}^1'],
                        capture_output=True,
                        text=True,
                        timeout=30
                    )

                    if check_result.returncode != 0:
                        # 检查 commit 本身是否存在
                        commit_check = subprocess.run(
                            ['git', '-C', pristine_repo_dir, 'rev-parse', commit_hash],
                            capture_output=True,
                            text=True,
                            timeout=30
                        )

                        if commit_check.returncode == 0:
                            # Commit 存在但没有父提交 = root commit
                            logger.info(f"Root commit detected | commit: {commit_hash[:12]}")
                            return {
                                'commit': commit_hash,
                                'parent': None,
                                'parent_count': 0,
                                'reason': 'root_commit'
                            }
                        else:
                            # Commit 不存在
                            logger.error(f"Commit not found | commit: {commit_hash[:12]}")
                            return None

            # 解析父提交列表
            parents = [p.strip() for p in result.stdout.strip().split('\n') if p.strip()]
            parent_count = len(parents)

            if parent_count == 0:
                # Root commit
                return {
                    'commit': commit_hash,
                    'parent': None,
                    'parent_count': 0,
                    'reason': 'root_commit'
                }

            # 获取第一个父提交的完整 hash
            first_parent = parents[0]

            response = {
                'commit': commit_hash,
                'parent': first_parent,
                'parent_count': parent_count
            }

            if parent_count > 1:
                logger.debug(f"Merge commit detected | commit: {commit_hash[:12]} | parents: {parent_count}")

            return response

        except subprocess.TimeoutExpired:
            logger.error(f"Query timed out | commit: {commit_hash[:12]}")
            return None
        except Exception as e:
            logger.error(f"Query failed | commit: {commit_hash[:12]} | error: {str(e)}")
            return None


# 单例实例（服务共享）
_query_instance = None


def get_query_instance() -> CommitTimeQuery:
    """获取全局查询实例"""
    global _query_instance
    if _query_instance is None:
        _query_instance = CommitTimeQuery()
    return _query_instance


if __name__ == '__main__':
    # 测试代码
    print("测试 CommitTimeQuery...")
    print("=" * 60)

    # 需要设置环境变量
    if 'CCI_SRC' not in os.environ:
        os.environ['CCI_SRC'] = '/srv/cci'
    if 'WORK_DIR' not in os.environ:
        os.environ['WORK_DIR'] = '/tmp'
    if 'LKP_SRC' not in os.environ:
        os.environ['LKP_SRC'] = '/srv/lkp'

    query = CommitTimeQuery()

    # 测试参数
    test_url = 'https://gitee.com/openeuler/kernel.git'
    test_commit = '5e5d40e65cb55e4699c9879674a004f246606a8d'

    print(f"\n测试仓库: {test_url}")
    print(f"测试 commit: {test_commit}")

    # 测试 1: 获取时间戳
    print("\n--- 测试 1: 获取时间戳 ---")
    timestamp = query.get_commit_timestamp(test_url, test_commit)
    if timestamp:
        print(f"时间戳: {timestamp}")
        print(f"日期: {datetime.utcfromtimestamp(timestamp).isoformat()}")
    else:
        print("查询失败")

    # 测试 2: 获取详细信息
    print("\n--- 测试 2: 获取详细信息 ---")
    info = query.get_commit_info(test_url, test_commit)
    if info:
        for key, value in info.items():
            print(f"  {key}: {value}")
    else:
        print("查询失败")

    # 测试 3: 检查是否过旧
    print("\n--- 测试 3: 检查是否超过 365 天 ---")
    is_old, age = query.is_commit_too_old(test_url, test_commit, max_age_days=365)
    if is_old is not None:
        print(f"距今: {age} 天")
        print(f"超过365天: {'是' if is_old else '否'}")
    else:
        print("查询失败")

    print("\n" + "=" * 60)
    print("测试完成")
