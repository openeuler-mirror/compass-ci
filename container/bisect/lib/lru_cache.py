#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
LRU (Least Recently Used) 缓存实现

用于替代简单的 Set 缓存，避免内存无限增长，提供自动淘汰机制。
"""

from collections import OrderedDict
from typing import Any, Optional
import time


class LRUCache:
    """
    基于 OrderedDict 的 LRU 缓存实现

    特性:
    - 固定大小，超出时自动淘汰最久未使用的项
    - O(1) 的查询和插入操作
    - 支持缓存命中率统计
    """

    def __init__(self, max_size: int = 5000):
        """
        初始化 LRU 缓存

        Args:
            max_size: 缓存最大容量
        """
        self.cache = OrderedDict()
        self.max_size = max_size

        # 统计信息
        self.hits = 0
        self.misses = 0
        self.evictions = 0

    def add(self, key: str, value: Any = True) -> None:
        """
        添加项到缓存

        Args:
            key: 缓存键
            value: 缓存值（默认为 True）
        """
        if key in self.cache:
            # 更新访问顺序
            self.cache.move_to_end(key)
        else:
            self.cache[key] = value
            # 检查容量
            if len(self.cache) > self.max_size:
                # 淘汰最久未使用的项
                evicted = self.cache.popitem(last=False)
                self.evictions += 1

    def get(self, key: str, default: Any = None) -> Any:
        """
        获取缓存项

        Args:
            key: 缓存键
            default: 默认值

        Returns:
            缓存值或默认值
        """
        if key in self.cache:
            self.hits += 1
            # 更新访问顺序
            self.cache.move_to_end(key)
            return self.cache[key]
        else:
            self.misses += 1
            return default

    def contains(self, key: str) -> bool:
        """
        检查键是否在缓存中

        Args:
            key: 缓存键

        Returns:
            是否存在
        """
        exists = key in self.cache
        if exists:
            self.hits += 1
            self.cache.move_to_end(key)
        else:
            self.misses += 1
        return exists

    def __contains__(self, key: str) -> bool:
        """支持 in 操作符"""
        return self.contains(key)

    def clear(self) -> None:
        """清空缓存"""
        self.cache.clear()

    def evict(self, key: str) -> bool:
        """
        移除指定键的缓存项

        Args:
            key: 缓存键

        Returns:
            是否成功移除（键存在则返回 True）
        """
        if key in self.cache:
            del self.cache[key]
            return True
        return False

    def size(self) -> int:
        """获取当前缓存大小"""
        return len(self.cache)

    def __len__(self) -> int:
        """支持 len() 函数"""
        return len(self.cache)

    def get_stats(self) -> dict:
        """
        获取缓存统计信息

        Returns:
            包含命中率等统计信息的字典
        """
        total_requests = self.hits + self.misses
        hit_rate = self.hits / total_requests if total_requests > 0 else 0

        return {
            'size': len(self.cache),
            'max_size': self.max_size,
            'hits': self.hits,
            'misses': self.misses,
            'hit_rate': hit_rate,
            'evictions': self.evictions,
            'total_requests': total_requests
        }

    def reset_stats(self) -> None:
        """重置统计信息"""
        self.hits = 0
        self.misses = 0
        self.evictions = 0


class TimedLRUCache(LRUCache):
    """
    带时间戳的 LRU 缓存

    支持基于时间的过期策略
    """

    def __init__(self, max_size: int = 5000, ttl_seconds: int = 3600):
        """
        初始化带时间戳的 LRU 缓存

        Args:
            max_size: 缓存最大容量
            ttl_seconds: 缓存项存活时间（秒）
        """
        super().__init__(max_size)
        self.ttl_seconds = ttl_seconds

    def add(self, key: str, value: Any = True) -> None:
        """添加带时间戳的缓存项"""
        timestamp = time.time()
        super().add(key, (value, timestamp))

    def get(self, key: str, default: Any = None) -> Any:
        """获取缓存项，检查是否过期"""
        if key not in self.cache:
            self.misses += 1
            return default

        value, timestamp = self.cache[key]

        # 检查是否过期
        if time.time() - timestamp > self.ttl_seconds:
            # 过期，删除并返回默认值
            del self.cache[key]
            self.misses += 1
            return default

        self.hits += 1
        self.cache.move_to_end(key)
        return value

    def cleanup_expired(self) -> int:
        """
        清理过期的缓存项

        Returns:
            清理的项数
        """
        current_time = time.time()
        expired_keys = []

        for key, (value, timestamp) in self.cache.items():
            if current_time - timestamp > self.ttl_seconds:
                expired_keys.append(key)

        for key in expired_keys:
            del self.cache[key]

        return len(expired_keys)