#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Commit Time Service Client

用于 bisect_producer 等客户端的简单封装
"""

import requests
from typing import Optional, Dict, Tuple


class CommitTimeClient:
    """Commit 时间服务客户端"""

    def __init__(self, service_url: str = 'http://localhost:8765', timeout: int = 10):
        """
        初始化客户端

        Args:
            service_url: 服务地址
            timeout: 请求超时时间（秒）
        """
        self.service_url = service_url.rstrip('/')
        self.timeout = timeout

    def get_commit_info(self, git_url: str, commit_hash: str) -> Optional[Dict]:
        """
        获取 commit 详细信息

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash

        Returns:
            Commit 信息字典，查询失败返回 None
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
            # 静默失败，返回 None
            return None

    def check_commit_age(self, git_url: str, commit_hash: str,
                        max_age_days: int = 365) -> Tuple[Optional[bool], Optional[int]]:
        """
        检查 commit 是否超过指定天数

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash
            max_age_days: 最大天数阈值

        Returns:
            (is_too_old, age_days)
            - is_too_old: True 表示超过阈值，None 表示查询失败
            - age_days: 实际天数，查询失败时为 None
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
            # 静默失败
            return (None, None)

    def is_commit_too_old(self, git_url: str, commit_hash: str,
                          max_age_days: int = 365) -> bool:
        """
        简单检查：commit 是否过旧（用于 producer 过滤）

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash
            max_age_days: 最大天数阈值

        Returns:
            True: commit 太旧应该过滤
            False: commit 可以使用或查询失败（降级策略）
        """
        is_old, age = self.check_commit_age(git_url, commit_hash, max_age_days)

        # 降级策略：查询失败时不过滤
        if is_old is None:
            return False

        return is_old

    def ping(self) -> bool:
        """
        检查服务是否可用

        Returns:
            True: 服务正常
            False: 服务不可用
        """
        try:
            response = requests.get(
                f"{self.service_url}/health",
                timeout=self.timeout
            )
            return response.status_code == 200
        except:
            return False


if __name__ == '__main__':
    # 示例用法
    client = CommitTimeClient('http://localhost:8765')

    # 测试服务是否可用
    if client.ping():
        print("Service is healthy")
    else:
        print("Service is not available")

    # 获取 commit 信息
    info = client.get_commit_info(
        'https://gitee.com/openeuler/kernel.git',
        '5e5d40e65cb55e4699c9879674a004f246606a8d'
    )
    if info:
        print(f"Commit: {info['commit']}")
        print(f"Age: {info['age_days']} days")
        print(f"Author: {info['author']}")

    # 检查是否过旧
    is_old = client.is_commit_too_old(
        'https://gitee.com/openeuler/kernel.git',
        '5e5d40e65cb55e4699c9879674a004f246606a8d',
        max_age_days=365
    )
    print(f"Is too old: {is_old}")
