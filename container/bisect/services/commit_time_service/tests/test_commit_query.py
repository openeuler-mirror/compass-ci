#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Unit tests for commit_query module
"""

import os
import sys
import unittest
from unittest.mock import Mock, patch, MagicMock

# 
os.environ['CCI_SRC'] = '/srv/cci'
os.environ['WORK_DIR'] = '/tmp'
os.environ['LKP_SRC'] = '/srv/lkp'

# 
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from commit_query import CommitTimeQuery


class TestCommitTimeQuery(unittest.TestCase):
    """CommitTimeQuery test"""

    def setUp(self):
        """test"""
        # Mock SharedRepoManager
        self.mock_repo_manager = Mock()
        self.mock_repo_manager.PRISTINE_BASE_DIR = '/tmp/test_pristine'
        self.mock_repo_manager.pristine_locks = {}
        self.mock_repo_manager.pristine_locks_lock = MagicMock()

        self.query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

    @patch.dict(os.environ, {'WORK_DIR': '/tmp/work_for_test'}, clear=False)
    def test_uses_dedicated_query_pristine_dir_by_default(self):
        q = CommitTimeQuery(repo_manager=self.mock_repo_manager)
        self.assertEqual(q.pristine_base_dir, '/tmp/work_for_test/bisect_repos/pristine_query')

    @patch('subprocess.run')
    @patch('os.path.exists')
    def test_get_commit_timestamp_success(self, mock_exists, mock_run):
        """testsuccessget commit """
        # Mock repo
        mock_exists.return_value = True

        # Mock git log success
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
        """test commit not found"""
        # Mock repo
        mock_exists.return_value = True

        # Mock git log failed（commit not found）
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
        """testsuccessget commit """
        # Mock repo
        mock_exists.return_value = True

        # Mock git log success
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
        """testget commit """
        # Mock repo
        mock_exists.return_value = True

        # Mock git log  30 
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
        self.assertGreaterEqual(age_days, 29)  # 
        self.assertLessEqual(age_days, 31)

    @patch('subprocess.run')
    @patch('os.path.exists')
    def test_is_commit_too_old(self, mock_exists, mock_run):
        """testcheck commit """
        # Mock repo
        mock_exists.return_value = True

        # test 1: 400  commit（ 365 ）
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

        # test 2: 30  commit（ 365 ）
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

    def test_invalid_params_return_none(self):
        """Empty or None params should return None (cannot determine)"""
        self.assertIsNone(self.query.is_ancestor('', 'abc', 'def'))
        self.assertIsNone(self.query.is_ancestor('http://repo', '', 'def'))
        self.assertIsNone(self.query.is_ancestor('http://repo', 'abc', ''))
        self.assertIsNone(self.query.is_ancestor(None, 'abc', 'def'))

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
    def test_is_ancestor_still_fails_after_fetch_returns_none(self, mock_run, mock_is_repo):
        """returncode 128 after fetch+retry should return None (not False)"""
        error_result = Mock()
        error_result.returncode = 128
        error_result.stderr = 'fatal: Not a valid object name'

        # First call 128, fetch succeeds, retry still 128
        mock_run.side_effect = [error_result, Mock(returncode=0), error_result]

        result = self.query.is_ancestor(
            'https://gitee.com/openeuler/kernel.git',
            'aaa111', 'bbb222'
        )
        self.assertIsNone(result)

    @patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
    @patch('subprocess.run')
    def test_is_ancestor_timeout(self, mock_run, mock_is_repo):
        """Timeout should return None (cannot determine)"""
        import subprocess
        mock_run.side_effect = subprocess.TimeoutExpired(cmd='git', timeout=30)

        result = self.query.is_ancestor(
            'https://gitee.com/openeuler/kernel.git',
            'aaa111', 'bbb222'
        )
        self.assertIsNone(result)

    @patch('commit_query.SharedRepoManager._is_git_repo', return_value=False)
    def test_is_ancestor_repo_clone_failure(self, mock_is_repo):
        """If pristine repo doesn't exist and clone fails, return None"""
        self.mock_repo_manager._ensure_pristine_repo.side_effect = Exception("clone failed")

        result = self.query.is_ancestor(
            'https://gitee.com/openeuler/kernel.git',
            'aaa111', 'bbb222'
        )
        self.assertIsNone(result)


class TestParentCommitDetailed(unittest.TestCase):
    """Tests for structured parent-commit query semantics."""

    def setUp(self):
        self.mock_repo_manager = Mock()
        self.mock_repo_manager.PRISTINE_BASE_DIR = '/tmp/test_pristine'
        self.mock_repo_manager.pristine_locks = {}
        self.mock_repo_manager.pristine_locks_lock = MagicMock()
        self.query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

    @patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
    @patch('subprocess.run')
    def test_parent_commit_detailed_allows_tag_or_ref_input(self, mock_run, _mock_is_repo):
        resolve_result = Mock(returncode=0, stdout='a' * 40 + '\n', stderr='')
        parent_result = Mock(returncode=0, stdout=('a' * 40) + ' ' + ('b' * 40) + '\n', stderr='')
        mock_run.side_effect = [resolve_result, parent_result]

        result = self.query.get_parent_commit_detailed(
            'https://gitee.com/openeuler/kernel.git',
            'v6.12.1'
        )

        self.assertEqual(result['status'], 'success')
        self.assertEqual(result['data']['parent'], 'b' * 40)
        self.assertEqual(result['data']['input_ref'], 'v6.12.1')

    @patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
    @patch('subprocess.run')
    def test_parent_commit_detailed_returns_commit_not_found(self, mock_run, _mock_is_repo):
        mock_run.return_value = Mock(returncode=1, stdout='', stderr='fatal: Needed a single revision')

        with patch.object(self.query, '_fetch_pristine_repo') as mock_fetch:
            result = self.query.get_parent_commit_detailed(
                'https://gitee.com/openeuler/kernel.git',
                'not-found-ref'
            )

        self.assertEqual(result['status'], 'error')
        self.assertEqual(result['error_code'], 'commit_not_found')
        self.assertFalse(result['retryable'])
        mock_fetch.assert_called_once()


if __name__ == '__main__':
    unittest.main()
