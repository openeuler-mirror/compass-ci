#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Unit tests for cache module
"""

import os
import sys
import unittest
import time

# 
os.environ['CCI_SRC'] = '/srv/cci'
os.environ['WORK_DIR'] = '/tmp'
os.environ['LKP_SRC'] = '/srv/lkp'

# 
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from cache import CommitTimeCache


class TestCommitTimeCache(unittest.TestCase):
    """CommitTimeCache test"""

    def setUp(self):
        """test"""
        self.cache = CommitTimeCache(max_size=100, ttl=2)  # 2TTLtest

    def test_timestamp_cache_hit(self):
        """test"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'abc123'
        timestamp = 1700000000

        # 
        self.cache.set_timestamp(git_url, commit, timestamp)

        # 
        cached_ts = self.cache.get_timestamp(git_url, commit)

        self.assertEqual(cached_ts, timestamp)

    def test_timestamp_cache_miss(self):
        """test"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'notexist'

        # not found
        cached_ts = self.cache.get_timestamp(git_url, commit)

        self.assertIsNone(cached_ts)

    def test_timestamp_cache_ttl(self):
        """test"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'abc123'
        timestamp = 1700000000

        # 
        self.cache.set_timestamp(git_url, commit, timestamp)

        # 
        cached_ts = self.cache.get_timestamp(git_url, commit)
        self.assertEqual(cached_ts, timestamp)

        #  TTL
        time.sleep(2.1)

        # 
        cached_ts = self.cache.get_timestamp(git_url, commit)
        self.assertIsNone(cached_ts)

    def test_info_cache_hit(self):
        """test"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'abc123'
        info = {
            'commit': commit,
            'timestamp': 1700000000,
            'age_days': 30
        }

        # 
        self.cache.set_info(git_url, commit, info)

        # 
        cached_info = self.cache.get_info(git_url, commit)

        self.assertIsNotNone(cached_info)
        self.assertEqual(cached_info['commit'], commit)
        self.assertEqual(cached_info['timestamp'], 1700000000)

    def test_info_cache_miss(self):
        """test"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'notexist'

        # not found
        cached_info = self.cache.get_info(git_url, commit)

        self.assertIsNone(cached_info)

    def test_cache_key_generation(self):
        """test key """
        git_url1 = 'https://gitee.com/openeuler/kernel.git'
        git_url2 = 'https://github.com/torvalds/linux.git'
        commit = 'abc123def456'

        # repo commit  key
        key1a = self.cache._make_key(git_url1, commit)
        key1b = self.cache._make_key(git_url1, commit)
        self.assertEqual(key1a, key1b)

        # repo key
        key2 = self.cache._make_key(git_url2, commit)
        self.assertNotEqual(key1a, key2)

        #  hash  hash  key
        short_commit = commit[:12]
        key_short = self.cache._make_key(git_url1, short_commit)
        self.assertEqual(key1a, key_short)

    def test_cache_stats(self):
        """teststats"""
        git_url = 'https://gitee.com/openeuler/kernel.git'

        # status
        stats = self.cache.get_stats()
        self.assertEqual(stats['timestamp_cache_size'], 0)

        # 
        for i in range(10):
            self.cache.set_timestamp(git_url, f'commit{i}', 1700000000 + i)

        stats = self.cache.get_stats()
        self.assertEqual(stats['timestamp_cache_size'], 10)

    def test_cache_clear(self):
        """test"""
        git_url = 'https://gitee.com/openeuler/kernel.git'

        # 
        self.cache.set_timestamp(git_url, 'abc123', 1700000000)
        self.cache.set_info(git_url, 'def456', {'commit': 'def456'})

        # 
        self.cache.clear()

        # verify
        self.assertIsNone(self.cache.get_timestamp(git_url, 'abc123'))
        self.assertIsNone(self.cache.get_info(git_url, 'def456'))

        stats = self.cache.get_stats()
        self.assertEqual(stats['timestamp_cache_size'], 0)


if __name__ == '__main__':
    unittest.main()
