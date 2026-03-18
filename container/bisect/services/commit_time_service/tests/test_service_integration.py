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

# 
os.environ['CCI_SRC'] = '/srv/cci'
os.environ['WORK_DIR'] = '/tmp'
os.environ['LKP_SRC'] = '/srv/lkp'

# 
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))


class TestServiceIntegration(unittest.TestCase):
    """servicetest"""

    @classmethod
    def setUpClass(cls):
        """testservice"""
        # service
        cls.server_process = subprocess.Popen(
            [sys.executable, os.path.join(os.path.dirname(__file__), '..', 'server.py'),
             '--port', '8766',  # 
             '--cache-size', '100'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        # service
        time.sleep(2)

        cls.base_url = 'http://localhost:8766'

    @classmethod
    def tearDownClass(cls):
        """testservice"""
        if cls.server_process:
            cls.server_process.terminate()
            cls.server_process.wait(timeout=5)

    def test_health_endpoint(self):
        """testcheck"""
        response = requests.get(f'{self.base_url}/health')

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['status'], 'healthy')

    def test_stats_endpoint(self):
        """teststats"""
        response = requests.get(f'{self.base_url}/api/v1/stats')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertIn('uptime_seconds', data)
        self.assertIn('total_requests', data)
        self.assertIn('cache_stats', data)

    def test_commit_time_endpoint_missing_params(self):
        """test"""
        #  commit 
        response = requests.get(
            f'{self.base_url}/api/v1/commit/time',
            params={'repo': 'https://gitee.com/openeuler/kernel.git'}
        )

        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertEqual(data['status'], 'error')

    def test_commit_check_endpoint_invalid_max_age(self):
        """test max_age_days """
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
        """testnot found"""
        response = requests.get(f'{self.base_url}/not/exist')

        self.assertEqual(response.status_code, 404)


class TestServiceFlow(unittest.TestCase):
    """servicetest（service）"""

    def test_service_initialization(self):
        """testserviceinitialize"""
        from server import CommitTimeService

        service = CommitTimeService(cache_size=100, cache_ttl=60)

        self.assertIsNotNone(service.query)
        self.assertIsNotNone(service.cache)
        self.assertEqual(service.request_count, 0)
        self.assertEqual(service.cache_hit_count, 0)

    def test_service_stats(self):
        """testservicestats"""
        from server import CommitTimeService

        service = CommitTimeService()

        stats = service.get_stats()

        self.assertIn('uptime_seconds', stats)
        self.assertIn('total_requests', stats)
        self.assertIn('cache_stats', stats)
        self.assertEqual(stats['total_requests'], 0)
        self.assertEqual(stats['cache_hits'], 0)


if __name__ == '__main__':
    # servicetest
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    #  TestServiceFlow test
    suite.addTests(loader.loadTestsFromTestCase(TestServiceFlow))

    # ：test，
    # suite.addTests(loader.loadTestsFromTestCase(TestServiceIntegration))

    runner = unittest.TextTestRunner(verbosity=2)
    runner.run(suite)
