#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Unit tests for cache module
"""

import os
import sys
import unittest
import time

# 设置环境变量
os.environ['CCI_SRC'] = '/srv/cci'
os.environ['WORK_DIR'] = '/tmp'
os.environ['LKP_SRC'] = '/srv/lkp'

# 添加项目路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from cache import CommitTimeCache


class TestCommitTimeCache(unittest.TestCase):
    """CommitTimeCache 单元测试"""

    def setUp(self):
        """测试前置"""
        self.cache = CommitTimeCache(max_size=100, ttl=2)  # 2秒TTL用于测试

    def test_timestamp_cache_hit(self):
        """测试时间戳缓存命中"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'abc123'
        timestamp = 1700000000

        # 设置缓存
        self.cache.set_timestamp(git_url, commit, timestamp)

        # 读取缓存
        cached_ts = self.cache.get_timestamp(git_url, commit)

        self.assertEqual(cached_ts, timestamp)

    def test_timestamp_cache_miss(self):
        """测试时间戳缓存未命中"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'notexist'

        # 读取不存在的缓存
        cached_ts = self.cache.get_timestamp(git_url, commit)

        self.assertIsNone(cached_ts)

    def test_timestamp_cache_ttl(self):
        """测试时间戳缓存过期"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'abc123'
        timestamp = 1700000000

        # 设置缓存
        self.cache.set_timestamp(git_url, commit, timestamp)

        # 立即读取应该命中
        cached_ts = self.cache.get_timestamp(git_url, commit)
        self.assertEqual(cached_ts, timestamp)

        # 等待超过 TTL
        time.sleep(2.1)

        # 再次读取应该过期
        cached_ts = self.cache.get_timestamp(git_url, commit)
        self.assertIsNone(cached_ts)

    def test_info_cache_hit(self):
        """测试详细信息缓存命中"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'abc123'
        info = {
            'commit': commit,
            'timestamp': 1700000000,
            'age_days': 30
        }

        # 设置缓存
        self.cache.set_info(git_url, commit, info)

        # 读取缓存
        cached_info = self.cache.get_info(git_url, commit)

        self.assertIsNotNone(cached_info)
        self.assertEqual(cached_info['commit'], commit)
        self.assertEqual(cached_info['timestamp'], 1700000000)

    def test_info_cache_miss(self):
        """测试详细信息缓存未命中"""
        git_url = 'https://gitee.com/openeuler/kernel.git'
        commit = 'notexist'

        # 读取不存在的缓存
        cached_info = self.cache.get_info(git_url, commit)

        self.assertIsNone(cached_info)

    def test_cache_key_generation(self):
        """测试缓存 key 生成"""
        git_url1 = 'https://gitee.com/openeuler/kernel.git'
        git_url2 = 'https://github.com/torvalds/linux.git'
        commit = 'abc123def456'

        # 同一仓库同一 commit 应该生成相同 key
        key1a = self.cache._make_key(git_url1, commit)
        key1b = self.cache._make_key(git_url1, commit)
        self.assertEqual(key1a, key1b)

        # 不同仓库应该生成不同 key
        key2 = self.cache._make_key(git_url2, commit)
        self.assertNotEqual(key1a, key2)

        # 简短 hash 和完整 hash 应该生成相同 key
        short_commit = commit[:12]
        key_short = self.cache._make_key(git_url1, short_commit)
        self.assertEqual(key1a, key_short)

    def test_cache_stats(self):
        """测试缓存统计"""
        git_url = 'https://gitee.com/openeuler/kernel.git'

        # 初始状态
        stats = self.cache.get_stats()
        self.assertEqual(stats['timestamp_cache_size'], 0)

        # 添加一些缓存
        for i in range(10):
            self.cache.set_timestamp(git_url, f'commit{i}', 1700000000 + i)

        stats = self.cache.get_stats()
        self.assertEqual(stats['timestamp_cache_size'], 10)

    def test_cache_clear(self):
        """测试清空缓存"""
        git_url = 'https://gitee.com/openeuler/kernel.git'

        # 添加缓存
        self.cache.set_timestamp(git_url, 'abc123', 1700000000)
        self.cache.set_info(git_url, 'def456', {'commit': 'def456'})

        # 清空
        self.cache.clear()

        # 验证已清空
        self.assertIsNone(self.cache.get_timestamp(git_url, 'abc123'))
        self.assertIsNone(self.cache.get_info(git_url, 'def456'))

        stats = self.cache.get_stats()
        self.assertEqual(stats['timestamp_cache_size'], 0)


if __name__ == '__main__':
    unittest.main()
