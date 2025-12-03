#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Bisect Producer Integration Example

演示如何在 bisect_producer 中集成 commit 年龄过滤
"""

import os
import sys
import re

# 添加 commit time service client 路径
sys.path.insert(0, os.path.join(os.environ.get('CCI_SRC', '/srv/cci'),
                                 'container/bisect/services/commit_time_service'))

from client import CommitTimeClient


def extract_commit_from_full_text_kv(full_text_kv: str) -> str:
    """
    从 full_text_kv 中提取 commit hash

    Args:
        full_text_kv: jobs 表的 full_text_kv 字段

    Returns:
        Commit hash，未找到返回空字符串
    """
    # 常见的 commit 模式
    patterns = [
        r'commit[:=]\s*([a-f0-9]{40})',          # commit: abc123...
        r'commit[:=]\s*([a-f0-9]{12,})',         # commit: abc123 (12+位)
        r'head[:=]\s*([a-f0-9]{40})',            # head: abc123...
        r'HEAD[:=]\s*([a-f0-9]{40})',            # HEAD: abc123...
    ]

    for pattern in patterns:
        match = re.search(pattern, full_text_kv, re.IGNORECASE)
        if match:
            return match.group(1)

    return ''


class BisectProducerWithCommitFilter:
    """
    集成 commit 年龄过滤的 Bisect Producer 示例

    这是一个演示类，展示如何集成到实际的 ErrorBisectProducer
    """

    def __init__(self, client, config):
        """初始化"""
        self.client = client
        self.config = config

        # 初始化 commit time client
        commit_service_url = config.get(
            'commit_time_service_url',
            os.environ.get('COMMIT_TIME_SERVICE_URL', 'http://localhost:8765')
        )
        self.commit_client = CommitTimeClient(commit_service_url)

        # commit 年龄阈值（天）
        self.max_commit_age_days = config.get(
            'max_commit_age_days',
            int(os.environ.get('BISECT_MAX_COMMIT_AGE_DAYS', '365'))
        )

        # 检查服务是否可用
        if self.commit_client.ping():
            print(f"Commit time service is available at {commit_service_url}")
        else:
            print(f"WARNING: Commit time service is NOT available at {commit_service_url}")
            print("Commit age filtering will be disabled (graceful degradation)")

    def should_filter_old_commit(self, git_url: str, full_text_kv: str) -> tuple:
        """
        检查是否应该过滤旧 commit

        Args:
            git_url: Git 仓库 URL
            full_text_kv: 作业的 full_text_kv

        Returns:
            (should_filter, reason)
            - should_filter: True 表示应该过滤
            - reason: 过滤原因（用于日志）
        """
        # 提取 commit
        commit_hash = extract_commit_from_full_text_kv(full_text_kv)

        if not commit_hash:
            # 无法提取 commit，不过滤（降级策略）
            return (False, 'no_commit_found')

        # 检查 commit 年龄
        is_old = self.commit_client.is_commit_too_old(
            git_url,
            commit_hash,
            max_age_days=self.max_commit_age_days
        )

        if is_old:
            return (True, f'commit_too_old (>{self.max_commit_age_days} days)')

        return (False, 'commit_age_ok')

    def execute_producer_cycle_example(self):
        """
        Producer 循环示例（简化版）

        展示如何在现有的 execute_producer_cycle 中集成 commit 过滤
        """
        stats = {
            'filtered_old_commits': 0,
            'commit_age_check_failed': 0,
        }

        # 模拟查询 jobs
        jobs = [
            {
                'id': 123456,
                'git_url': 'https://gitee.com/openeuler/kernel.git',
                'full_text_kv': 'commit: abc123def456...',
                'error_ids': ['error1', 'error2']
            }
        ]

        for job in jobs:
            git_url = job.get('git_url')
            full_text_kv = job.get('full_text_kv', '')

            if not git_url:
                continue

            # 检查 commit 年龄
            should_filter, reason = self.should_filter_old_commit(git_url, full_text_kv)

            if should_filter:
                stats['filtered_old_commits'] += 1
                print(f"Filtered old commit | job_id: {job['id']} | reason: {reason}")
                continue  # 跳过这个 job

            # ... 继续处理其他逻辑（创建 bisect 任务等）

        print(f"\n统计:")
        print(f"  过滤的旧 commit: {stats['filtered_old_commits']}")


def integration_example():
    """集成示例"""
    print("=" * 60)
    print("Bisect Producer Commit Age Filter Integration Example")
    print("=" * 60)

    # 模拟配置
    config = {
        'commit_time_service_url': 'http://localhost:8765',
        'max_commit_age_days': 365
    }

    # 创建 producer（这里使用示例类）
    producer = BisectProducerWithCommitFilter(None, config)

    # 测试单个 commit 过滤
    print("\n测试单个 commit 过滤:")
    print("-" * 60)

    test_cases = [
        {
            'git_url': 'https://gitee.com/openeuler/kernel.git',
            'full_text_kv': 'commit: 5e5d40e65cb55e4699c9879674a004f246606a8d',
            'desc': '正常的最近 commit'
        },
        {
            'git_url': 'https://gitee.com/openeuler/kernel.git',
            'full_text_kv': 'no commit here',
            'desc': '没有 commit 信息'
        }
    ]

    for test in test_cases:
        should_filter, reason = producer.should_filter_old_commit(
            test['git_url'],
            test['full_text_kv']
        )
        print(f"{test['desc']}:")
        print(f"  过滤: {should_filter} | 原因: {reason}")

    print("\n" + "=" * 60)


if __name__ == '__main__':
    integration_example()
