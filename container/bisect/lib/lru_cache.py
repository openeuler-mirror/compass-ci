#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
LRU (Least Recently Used) 

 Set ，，。
"""

from collections import OrderedDict
from typing import Any, Optional
import time


class LRUCache:
    """
     OrderedDict  LRU 

    :
    - ，
    - O(1) query
    - supportstats
    """

    def __init__(self, max_size: int = 5000):
        """
        initialize LRU 

        Args:
            max_size: 
        """
        self.cache = OrderedDict()
        self.max_size = max_size

        # stats
        self.hits = 0
        self.misses = 0
        self.evictions = 0

    def add(self, key: str, value: Any = True) -> None:
        """
        

        Args:
            key: 
            value: （default True）
        """
        if key in self.cache:
            # 
            self.cache.move_to_end(key)
        else:
            self.cache[key] = value
            # check
            if len(self.cache) > self.max_size:
                # 
                evicted = self.cache.popitem(last=False)
                self.evictions += 1

    def get(self, key: str, default: Any = None) -> Any:
        """
        get

        Args:
            key: 
            default: default

        Returns:
            default
        """
        if key in self.cache:
            self.hits += 1
            # 
            self.cache.move_to_end(key)
            return self.cache[key]
        else:
            self.misses += 1
            return default

    def contains(self, key: str) -> bool:
        """
        check

        Args:
            key: 

        Returns:
            
        """
        exists = key in self.cache
        if exists:
            self.hits += 1
            self.cache.move_to_end(key)
        else:
            self.misses += 1
        return exists

    def __contains__(self, key: str) -> bool:
        """support in """
        return self.contains(key)

    def clear(self) -> None:
        """"""
        self.cache.clear()

    def evict(self, key: str) -> bool:
        """
        

        Args:
            key: 

        Returns:
            success（ True）
        """
        if key in self.cache:
            del self.cache[key]
            return True
        return False

    def size(self) -> int:
        """get"""
        return len(self.cache)

    def __len__(self) -> int:
        """support len() """
        return len(self.cache)

    def get_stats(self) -> dict:
        """
        getstats

        Returns:
            statsdict
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
        """resetstats"""
        self.hits = 0
        self.misses = 0
        self.evictions = 0


class TimedLRUCache(LRUCache):
    """
     LRU 

    support
    """

    def __init__(self, max_size: int = 5000, ttl_seconds: int = 3600):
        """
        initialize LRU 

        Args:
            max_size: 
            ttl_seconds: （）
        """
        super().__init__(max_size)
        self.ttl_seconds = ttl_seconds

    def add(self, key: str, value: Any = True) -> None:
        """"""
        timestamp = time.time()
        super().add(key, (value, timestamp))

    def get(self, key: str, default: Any = None) -> Any:
        """get，check"""
        if key not in self.cache:
            self.misses += 1
            return default

        value, timestamp = self.cache[key]

        # check
        if time.time() - timestamp > self.ttl_seconds:
            # ，deletedefault
            del self.cache[key]
            self.misses += 1
            return default

        self.hits += 1
        self.cache.move_to_end(key)
        return value

    def cleanup_expired(self) -> int:
        """
        

        Returns:
            
        """
        current_time = time.time()
        expired_keys = []

        for key, (value, timestamp) in self.cache.items():
            if current_time - timestamp > self.ttl_seconds:
                expired_keys.append(key)

        for key in expired_keys:
            del self.cache[key]

        return len(expired_keys)