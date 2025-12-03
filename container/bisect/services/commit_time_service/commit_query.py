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
from typing import Optional, Dict, Tuple
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

        # 确保 pristine 仓库存在
        if not os.path.exists(os.path.join(pristine_repo_dir, ".git")):
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

        # 确保 pristine 仓库存在
        if not os.path.exists(os.path.join(pristine_repo_dir, ".git")):
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
        """更新 pristine 仓库"""
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
