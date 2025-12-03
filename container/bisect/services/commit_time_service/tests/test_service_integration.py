#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Integration tests for Commit Time Service
"""

import os
import sys
import unittest
import time
import requests
import threading
import subprocess

# 设置环境变量
os.environ['CCI_SRC'] = '/srv/cci'
os.environ['WORK_DIR'] = '/tmp'
os.environ['LKP_SRC'] = '/srv/lkp'

# 添加项目路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))


class TestServiceIntegration(unittest.TestCase):
    """服务集成测试"""

    @classmethod
    def setUpClass(cls):
        """启动测试服务器"""
        # 启动服务器进程
        cls.server_process = subprocess.Popen(
            [sys.executable, os.path.join(os.path.dirname(__file__), '..', 'server.py'),
             '--port', '8766',  # 使用不同端口避免冲突
             '--cache-size', '100'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        # 等待服务器启动
        time.sleep(2)

        cls.base_url = 'http://localhost:8766'

    @classmethod
    def tearDownClass(cls):
        """停止测试服务器"""
        if cls.server_process:
            cls.server_process.terminate()
            cls.server_process.wait(timeout=5)

    def test_health_endpoint(self):
        """测试健康检查端点"""
        response = requests.get(f'{self.base_url}/health')

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['status'], 'healthy')

    def test_stats_endpoint(self):
        """测试统计端点"""
        response = requests.get(f'{self.base_url}/api/v1/stats')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertIn('uptime_seconds', data)
        self.assertIn('total_requests', data)
        self.assertIn('cache_stats', data)

    def test_commit_time_endpoint_missing_params(self):
        """测试缺少参数的情况"""
        # 缺少 commit 参数
        response = requests.get(
            f'{self.base_url}/api/v1/commit/time',
            params={'repo': 'https://gitee.com/openeuler/kernel.git'}
        )

        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertEqual(data['status'], 'error')

    def test_commit_check_endpoint_invalid_max_age(self):
        """测试无效的 max_age_days 参数"""
        response = requests.get(
            f'{self.base_url}/api/v1/commit/check',
            params={
                'repo': 'https://gitee.com/openeuler/kernel.git',
                'commit': 'abc123',
                'max_age_days': 'invalid'
            }
        )

        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertEqual(data['status'], 'error')

    def test_404_endpoint(self):
        """测试不存在的端点"""
        response = requests.get(f'{self.base_url}/not/exist')

        self.assertEqual(response.status_code, 404)


class TestServiceFlow(unittest.TestCase):
    """服务流程测试（不启动真实服务器）"""

    def test_service_initialization(self):
        """测试服务初始化"""
        from server import CommitTimeService

        service = CommitTimeService(cache_size=100, cache_ttl=60)

        self.assertIsNotNone(service.query)
        self.assertIsNotNone(service.cache)
        self.assertEqual(service.request_count, 0)
        self.assertEqual(service.cache_hit_count, 0)

    def test_service_stats(self):
        """测试服务统计"""
        from server import CommitTimeService

        service = CommitTimeService()

        stats = service.get_stats()

        self.assertIn('uptime_seconds', stats)
        self.assertIn('total_requests', stats)
        self.assertIn('cache_stats', stats)
        self.assertEqual(stats['total_requests'], 0)
        self.assertEqual(stats['cache_hits'], 0)


if __name__ == '__main__':
    # 仅运行不需要真实服务器的测试
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # 添加 TestServiceFlow 的所有测试
    suite.addTests(loader.loadTestsFromTestCase(TestServiceFlow))

    # 可选：如果需要集成测试，取消注释下一行
    # suite.addTests(loader.loadTestsFromTestCase(TestServiceIntegration))

    runner = unittest.TextTestRunner(verbosity=2)
    runner.run(suite)
