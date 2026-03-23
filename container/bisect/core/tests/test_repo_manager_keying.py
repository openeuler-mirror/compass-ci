#!/usr/bin/env python3
"""Tests for repo key normalization and fetch timestamp keying in SharedRepoManager."""

import os
import sys
import tempfile
import unittest
from contextlib import nullcontext
from unittest.mock import MagicMock, patch


os.environ.setdefault('WORK_DIR', '/tmp')
os.environ.setdefault('LKP_SRC', '/tmp')
os.environ.setdefault('CCI_SRC', '/tmp')
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'lib'))

from repo_manager import SharedRepoManager


class TestRepoManagerKeying(unittest.TestCase):
    def test_canonical_repo_key_normalizes_equivalent_urls(self):
        key1 = SharedRepoManager._canonical_repo_key('git+https://gitee.com/openeuler/kernel.git/')
        key2 = SharedRepoManager._canonical_repo_key('https://gitee.com/openeuler/kernel')
        self.assertEqual(key1, key2)
        self.assertEqual(key1, 'https://gitee.com/openeuler/kernel')

    def test_fetch_interval_uses_canonical_key(self):
        manager = SharedRepoManager.__new__(SharedRepoManager)
        manager.pristine_fetch_timestamps = {}
        manager.PRISTINE_FETCH_INTERVAL = 999999
        manager._clone_repo_atomic = MagicMock()
        manager._recreate_pristine_repo_atomic = MagicMock()
        manager._fetch_repo = MagicMock()

        with patch.object(SharedRepoManager, '_is_git_repo', return_value=True):
            manager._ensure_pristine_repo('git+https://gitee.com/openeuler/kernel.git/', '/tmp/pristine/kernel')
            manager._ensure_pristine_repo('https://gitee.com/openeuler/kernel', '/tmp/pristine/kernel')

        # Same canonical key should make second call skip fetch due to interval throttle.
        manager._fetch_repo.assert_called_once()

    def test_pristine_lockfile_path_uses_canonical_key(self):
        manager = SharedRepoManager.__new__(SharedRepoManager)
        manager.PRISTINE_BASE_DIR = '/tmp/bisect_repos/pristine'

        with patch('repo_manager.extract_repo_name_from_url', return_value='kernel'):
            p1 = manager._pristine_lockfile_path(
                'git+https://gitee.com/openeuler/kernel.git/',
                '/tmp/bisect_repos/pristine/kernel'
            )
            p2 = manager._pristine_lockfile_path(
                'https://gitee.com/openeuler/kernel',
                '/tmp/bisect_repos/pristine/kernel'
            )
        self.assertEqual(p1, p2)
        self.assertTrue(p1.endswith('.lock'))

    def test_get_repo_dir_wraps_ensure_and_clone_with_file_lock(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            manager = SharedRepoManager.__new__(SharedRepoManager)
            manager.PRISTINE_BASE_DIR = os.path.join(tmpdir, 'pristine')
            manager.REPO_BASE_DIR = os.path.join(tmpdir, 'workspaces')
            manager.pristine_locks = {}
            manager.pristine_locks_lock = MagicMock()
            manager._ensure_pristine_repo = MagicMock()
            manager._clone_workspace_repo = MagicMock()
            manager._cleanup_stale_locks = MagicMock()
            os.makedirs(manager.PRISTINE_BASE_DIR, exist_ok=True)
            os.makedirs(manager.REPO_BASE_DIR, exist_ok=True)

            with patch('repo_manager.extract_repo_name_from_url', return_value='kernel'):
                with patch.object(manager, '_pristine_file_lock', return_value=nullcontext()) as mock_file_lock:
                    manager.get_repo_dir(123, 'job', 'https://gitee.com/openeuler/kernel.git')

            pristine_repo_dir = os.path.join(manager.PRISTINE_BASE_DIR, 'kernel')
            mock_file_lock.assert_called_once_with('https://gitee.com/openeuler/kernel.git', pristine_repo_dir)
            manager._ensure_pristine_repo.assert_called_once()
            manager._clone_workspace_repo.assert_called_once()


if __name__ == '__main__':
    unittest.main()
