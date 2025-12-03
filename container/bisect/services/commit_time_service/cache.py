#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Commit Time Cache - commit 时间查询缓存

使用 LRU 缓存减少重复的 git 操作
"""

import os
import sys
import time
from typing import Optional, Dict

# 添加项目路径
lib_path = os.path.join(os.environ.get('CCI_SRC', '/srv/cci'), 'container/bisect/lib')
if lib_path not in sys.path:
    sys.path.insert(0, lib_path)

from lru_cache import LRUCache


class CommitTimeCache:
    """Commit 时间缓存器"""

    def __init__(self, max_size: int = 10000, ttl: int = 86400):
        """
        初始化缓存

        Args:
            max_size: 最大缓存条目数
            ttl: 缓存过期时间（秒），默认24小时
        """
        self.cache = LRUCache(max_size=max_size)
        self.ttl = ttl
        # 时间戳缓存，格式: key -> (timestamp, cached_time)
        self.timestamp_cache = {}

    def _make_key(self, git_url: str, commit_hash: str) -> str:
        """生成缓存 key"""
        # 使用前12位 commit hash 足够了
        short_hash = commit_hash[:12] if len(commit_hash) > 12 else commit_hash
        return f"{git_url}|{short_hash}"

    def get_timestamp(self, git_url: str, commit_hash: str) -> Optional[int]:
        """
        从缓存获取 commit 时间戳

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash

        Returns:
            Unix 时间戳，如果缓存未命中或已过期返回 None
        """
        key = self._make_key(git_url, commit_hash)

        if key in self.timestamp_cache:
            timestamp, cached_time = self.timestamp_cache[key]

            # 检查是否过期
            if time.time() - cached_time < self.ttl:
                return timestamp
            else:
                # 过期，删除
                del self.timestamp_cache[key]
                return None

        return None

    def set_timestamp(self, git_url: str, commit_hash: str, timestamp: int):
        """
        设置 commit 时间戳到缓存

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash
            timestamp: Unix 时间戳
        """
        key = self._make_key(git_url, commit_hash)
        self.timestamp_cache[key] = (timestamp, time.time())

        # 如果超过最大size，清理最久未使用的
        if len(self.timestamp_cache) > self.cache.max_size:
            self._cleanup_old_entries()

    def get_info(self, git_url: str, commit_hash: str) -> Optional[Dict]:
        """
        从缓存获取 commit 详细信息

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash

        Returns:
            Commit 信息字典，如果缓存未命中或已过期返回 None
        """
        key = self._make_key(git_url, commit_hash)

        if key in self.cache:
            info, cached_time = self.cache.get(key)

            # 检查是否过期
            if time.time() - cached_time < self.ttl:
                return info
            else:
                # 过期，删除
                self.cache.evict(key)
                return None

        return None

    def set_info(self, git_url: str, commit_hash: str, info: Dict):
        """
        设置 commit 详细信息到缓存

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash
            info: Commit 信息字典
        """
        key = self._make_key(git_url, commit_hash)
        self.cache.add(key, (info, time.time()))

    def _cleanup_old_entries(self):
        """清理过期条目"""
        now = time.time()
        expired_keys = []

        for key, (timestamp, cached_time) in self.timestamp_cache.items():
            if now - cached_time >= self.ttl:
                expired_keys.append(key)

        for key in expired_keys:
            del self.timestamp_cache[key]

    def clear(self):
        """清空缓存"""
        self.cache.clear()
        self.timestamp_cache.clear()

    def get_stats(self) -> Dict:
        """获取缓存统计信息"""
        cache_stats = self.cache.get_stats()
        return {
            'timestamp_cache_size': len(self.timestamp_cache),
            'info_cache_size': cache_stats['size'],
            'max_size': self.cache.max_size,
            'ttl': self.ttl,
            'hit_rate': cache_stats['hit_rate'],
            'evictions': cache_stats['evictions']
        }


if __name__ == '__main__':
    # 测试代码
    print("测试 CommitTimeCache...")
    print("=" * 60)

    cache = CommitTimeCache(max_size=100, ttl=60)

    test_url = 'https://gitee.com/openeuler/kernel.git'
    test_commit = '5e5d40e65cb55e4699c9879674a004f246606a8d'

    # 测试 1: 设置和获取时间戳
    print("\n--- 测试 1: 时间戳缓存 ---")
    print("设置缓存...")
    cache.set_timestamp(test_url, test_commit, 1700000000)

    print("获取缓存...")
    ts = cache.get_timestamp(test_url, test_commit)
    print(f"缓存命中: {ts}")

    # 测试 2: 设置和获取详细信息
    print("\n--- 测试 2: 详细信息缓存 ---")
    test_info = {
        'commit': test_commit,
        'timestamp': 1700000000,
        'age_days': 30,
        'author': 'Test Author',
        'subject': 'Test Subject'
    }

    print("设置缓存...")
    cache.set_info(test_url, test_commit, test_info)

    print("获取缓存...")
    info = cache.get_info(test_url, test_commit)
    if info:
        print(f"缓存命中:")
        for k, v in info.items():
            print(f"  {k}: {v}")
    else:
        print("缓存未命中")

    # 测试 3: 统计信息
    print("\n--- 测试 3: 统计信息 ---")
    stats = cache.get_stats()
    for key, value in stats.items():
        print(f"  {key}: {value}")

    print("\n" + "=" * 60)
    print("测试完成")
