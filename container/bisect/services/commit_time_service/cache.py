#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Commit Time Cache - commit query

 LRU duplicate git 
"""

import os
import sys
import time
from typing import Optional, Dict

# 
lib_path = os.path.join(os.environ.get('CCI_SRC', '/srv/cci'), 'container/bisect/lib')
if lib_path not in sys.path:
    sys.path.insert(0, lib_path)

from lru_cache import LRUCache


class CommitTimeCache:
    """Commit """

    def __init__(self, max_size: int = 10000, ttl: int = 86400):
        """
        initialize

        Args:
            max_size: 
            ttl: （），default24
        """
        self.cache = LRUCache(max_size=max_size)
        self.ttl = ttl
        # ，: key -> (timestamp, cached_time)
        self.timestamp_cache = {}

    def _make_key(self, git_url: str, commit_hash: str) -> str:
        """ key"""
        # 12 commit hash 
        short_hash = commit_hash[:12] if len(commit_hash) > 12 else commit_hash
        return f"{git_url}|{short_hash}"

    def get_timestamp(self, git_url: str, commit_hash: str) -> Optional[int]:
        """
        get commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash

        Returns:
            Unix ， None
        """
        key = self._make_key(git_url, commit_hash)

        if key in self.timestamp_cache:
            timestamp, cached_time = self.timestamp_cache[key]

            # check
            if time.time() - cached_time < self.ttl:
                return timestamp
            else:
                # ，delete
                del self.timestamp_cache[key]
                return None

        return None

    def set_timestamp(self, git_url: str, commit_hash: str, timestamp: int):
        """
         commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash
            timestamp: Unix 
        """
        key = self._make_key(git_url, commit_hash)
        self.timestamp_cache[key] = (timestamp, time.time())

        # size，
        if len(self.timestamp_cache) > self.cache.max_size:
            self._cleanup_old_entries()

    def get_info(self, git_url: str, commit_hash: str) -> Optional[Dict]:
        """
        get commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash

        Returns:
            Commit dict， None
        """
        key = self._make_key(git_url, commit_hash)

        if key in self.cache:
            info, cached_time = self.cache.get(key)

            # check
            if time.time() - cached_time < self.ttl:
                return info
            else:
                # ，delete
                self.cache.evict(key)
                return None

        return None

    def set_info(self, git_url: str, commit_hash: str, info: Dict):
        """
         commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash
            info: Commit dict
        """
        key = self._make_key(git_url, commit_hash)
        self.cache.add(key, (info, time.time()))

    def get(self, key: str) -> Optional[Dict]:
        """
        get（ parent commit ）

        Args:
            key: 

        Returns:
            ， None
        """
        if key in self.cache:
            data, cached_time = self.cache.get(key)

            # check
            if time.time() - cached_time < self.ttl:
                return data
            else:
                self.cache.evict(key)
                return None

        return None

    def set(self, key: str, data: Dict):
        """
        （ parent commit ）

        Args:
            key: 
            data: 
        """
        self.cache.add(key, (data, time.time()))

    def _cleanup_old_entries(self):
        """"""
        now = time.time()
        expired_keys = []

        for key, (timestamp, cached_time) in self.timestamp_cache.items():
            if now - cached_time >= self.ttl:
                expired_keys.append(key)

        for key in expired_keys:
            del self.timestamp_cache[key]

    def clear(self):
        """"""
        self.cache.clear()
        self.timestamp_cache.clear()

    def get_stats(self) -> Dict:
        """getstats"""
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
    # test
    print("test CommitTimeCache...")
    print("=" * 60)

    cache = CommitTimeCache(max_size=100, ttl=60)

    test_url = 'https://gitee.com/openeuler/kernel.git'
    test_commit = '5e5d40e65cb55e4699c9879674a004f246606a8d'

    # test 1: get
    print("\n--- test 1:  ---")
    print("...")
    cache.set_timestamp(test_url, test_commit, 1700000000)

    print("get...")
    ts = cache.get_timestamp(test_url, test_commit)
    print(f": {ts}")

    # test 2: get
    print("\n--- test 2:  ---")
    test_info = {
        'commit': test_commit,
        'timestamp': 1700000000,
        'age_days': 30,
        'author': 'Test Author',
        'subject': 'Test Subject'
    }

    print("...")
    cache.set_info(test_url, test_commit, test_info)

    print("get...")
    info = cache.get_info(test_url, test_commit)
    if info:
        print(f":")
        for k, v in info.items():
            print(f"  {k}: {v}")
    else:
        print("")

    # test 3: stats
    print("\n--- test 3: stats ---")
    stats = cache.get_stats()
    for key, value in stats.items():
        print(f"  {key}: {value}")

    print("\n" + "=" * 60)
    print("testcompleted")
