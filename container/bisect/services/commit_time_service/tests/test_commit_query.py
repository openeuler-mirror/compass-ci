#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Unit tests for commit_query module
"""

import os
import sys
import unittest
from unittest.mock import Mock, patch, MagicMock

# 设置环境变量
os.environ['CCI_SRC'] = '/srv/cci'
os.environ['WORK_DIR'] = '/tmp'
os.environ['LKP_SRC'] = '/srv/lkp'

# 添加项目路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from commit_query import CommitTimeQuery


class TestCommitTimeQuery(unittest.TestCase):
    """CommitTimeQuery 单元测试"""

    def setUp(self):
        """测试前置"""
        # Mock SharedRepoManager
        self.mock_repo_manager = Mock()
        self.mock_repo_manager.PRISTINE_BASE_DIR = '/tmp/test_pristine'
        self.mock_repo_manager.pristine_locks = {}
        self.mock_repo_manager.pristine_locks_lock = MagicMock()

        self.query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

    @patch('subprocess.run')
    @patch('os.path.exists')
    def test_get_commit_timestamp_success(self, mock_exists, mock_run):
        """测试成功获取 commit 时间戳"""
        # Mock 仓库存在
        mock_exists.return_value = True

        # Mock git log 命令成功
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = '1700000000\n'
        mock_run.return_value = mock_result

        timestamp = self.query.get_commit_timestamp(
            'https://gitee.com/openeuler/kernel.git',
            'abc123'
        )

        self.assertEqual(timestamp, 1700000000)
        self.assertTrue(mock_run.called)

    @patch('subprocess.run')
    @patch('os.path.exists')
    def test_get_commit_timestamp_not_found(self, mock_exists, mock_run):
        """测试 commit 不存在的情况"""
        # Mock 仓库存在
        mock_exists.return_value = True

        # Mock git log 失败（commit 不存在）
        mock_result = Mock()
        mock_result.returncode = 128
        mock_result.stderr = 'fatal: bad revision'
        mock_run.return_value = mock_result

        timestamp = self.query.get_commit_timestamp(
            'https://gitee.com/openeuler/kernel.git',
            'notexist'
        )

        self.assertIsNone(timestamp)

    @patch('subprocess.run')
    @patch('os.path.exists')
    def test_get_commit_info_success(self, mock_exists, mock_run):
        """测试成功获取 commit 详细信息"""
        # Mock 仓库存在
        mock_exists.return_value = True

        # Mock git log 命令成功
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = 'abc123def456|1700000000|Zhang San|fix: some bug\n'
        mock_run.return_value = mock_result

        info = self.query.get_commit_info(
            'https://gitee.com/openeuler/kernel.git',
            'abc123'
        )

        self.assertIsNotNone(info)
        self.assertEqual(info['commit'], 'abc123def456')
        self.assertEqual(info['timestamp'], 1700000000)
        self.assertEqual(info['author'], 'Zhang San')
        self.assertEqual(info['subject'], 'fix: some bug')
        self.assertIn('age_days', info)
        self.assertIn('date', info)

    @patch('subprocess.run')
    @patch('os.path.exists')
    def test_get_commit_age_days(self, mock_exists, mock_run):
        """测试获取 commit 年龄"""
        # Mock 仓库存在
        mock_exists.return_value = True

        # Mock git log 返回 30 天前的时间戳
        import time
        timestamp_30_days_ago = int(time.time()) - (30 * 86400)

        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = f'{timestamp_30_days_ago}\n'
        mock_run.return_value = mock_result

        age_days = self.query.get_commit_age_days(
            'https://gitee.com/openeuler/kernel.git',
            'abc123'
        )

        self.assertIsNotNone(age_days)
        self.assertGreaterEqual(age_days, 29)  # 允许一些误差
        self.assertLessEqual(age_days, 31)

    @patch('subprocess.run')
    @patch('os.path.exists')
    def test_is_commit_too_old(self, mock_exists, mock_run):
        """测试检查 commit 是否过旧"""
        # Mock 仓库存在
        mock_exists.return_value = True

        # 测试 1: 400 天前的 commit（超过 365 天）
        import time
        timestamp_400_days_ago = int(time.time()) - (400 * 86400)

        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = f'{timestamp_400_days_ago}\n'
        mock_run.return_value = mock_result

        is_old, age = self.query.is_commit_too_old(
            'https://gitee.com/openeuler/kernel.git',
            'old_commit',
            max_age_days=365
        )

        self.assertTrue(is_old)
        self.assertGreaterEqual(age, 399)

        # 测试 2: 30 天前的 commit（未超过 365 天）
        timestamp_30_days_ago = int(time.time()) - (30 * 86400)

        mock_result.stdout = f'{timestamp_30_days_ago}\n'
        mock_run.return_value = mock_result

        is_old, age = self.query.is_commit_too_old(
            'https://gitee.com/openeuler/kernel.git',
            'recent_commit',
            max_age_days=365
        )

        self.assertFalse(is_old)
        self.assertLessEqual(age, 31)


class TestIsAncestor(unittest.TestCase):
    """Unit tests for CommitTimeQuery.is_ancestor"""

    def setUp(self):
        self.mock_repo_manager = Mock()
        self.mock_repo_manager.PRISTINE_BASE_DIR = '/tmp/test_pristine'
        self.mock_repo_manager.pristine_locks = {}
        self.mock_repo_manager.pristine_locks_lock = MagicMock()
        self.query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

    def test_invalid_params_return_false(self):
        """Empty or None params should return False"""
        self.assertFalse(self.query.is_ancestor('', 'abc', 'def'))
        self.assertFalse(self.query.is_ancestor('http://repo', '', 'def'))
        self.assertFalse(self.query.is_ancestor('http://repo', 'abc', ''))
        self.assertFalse(self.query.is_ancestor(None, 'abc', 'def'))

    @patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
    @patch('subprocess.run')
    def test_is_ancestor_true(self, mock_run, mock_is_repo):
        """returncode 0 means ancestor relationship exists"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_run.return_value = mock_result

        result = self.query.is_ancestor(
            'https://gitee.com/openeuler/kernel.git',
            'aaa111', 'bbb222'
        )
        self.assertTrue(result)
        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        self.assertIn('merge-base', args)
        self.assertIn('--is-ancestor', args)

    @patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
    @patch('subprocess.run')
    def test_is_ancestor_false(self, mock_run, mock_is_repo):
        """returncode 1 means not an ancestor"""
        mock_result = Mock()
        mock_result.returncode = 1
        mock_run.return_value = mock_result

        result = self.query.is_ancestor(
            'https://gitee.com/openeuler/kernel.git',
            'aaa111', 'bbb222'
        )
        self.assertFalse(result)
        # Should NOT fetch and retry on returncode 1
        mock_run.assert_called_once()

    @patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
    @patch('subprocess.run')
    def test_is_ancestor_error_triggers_fetch_and_retry(self, mock_run, mock_is_repo):
        """returncode 128 (bad commit) should fetch and retry"""
        error_result = Mock()
        error_result.returncode = 128
        error_result.stderr = 'fatal: Not a valid object name'

        success_result = Mock()
        success_result.returncode = 0

        # First call fails with 128, fetch call, then retry succeeds
        mock_run.side_effect = [error_result, Mock(returncode=0), success_result]

        result = self.query.is_ancestor(
            'https://gitee.com/openeuler/kernel.git',
            'aaa111', 'bbb222'
        )
        self.assertTrue(result)
        # 3 calls: initial check, fetch, retry
        self.assertEqual(mock_run.call_count, 3)

    @patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
    @patch('subprocess.run')
    def test_is_ancestor_timeout(self, mock_run, mock_is_repo):
        """Timeout should return False gracefully"""
        import subprocess
        mock_run.side_effect = subprocess.TimeoutExpired(cmd='git', timeout=30)

        result = self.query.is_ancestor(
            'https://gitee.com/openeuler/kernel.git',
            'aaa111', 'bbb222'
        )
        self.assertFalse(result)

    @patch('commit_query.SharedRepoManager._is_git_repo', return_value=False)
    def test_is_ancestor_repo_clone_failure(self, mock_is_repo):
        """If pristine repo doesn't exist and clone fails, return False"""
        self.mock_repo_manager._ensure_pristine_repo.side_effect = Exception("clone failed")

        result = self.query.is_ancestor(
            'https://gitee.com/openeuler/kernel.git',
            'aaa111', 'bbb222'
        )
        self.assertFalse(result)


if __name__ == '__main__':
    unittest.main()
