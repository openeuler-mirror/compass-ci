#!/usr/bin/env python3
"""Real-fs tests for SharedRepoManager.cleanup_task_workspace."""

import os
import sys
import tempfile
import unittest


os.environ.setdefault('WORK_DIR', '/tmp')
os.environ.setdefault('LKP_SRC', '/tmp')
os.environ.setdefault('CCI_SRC', '/tmp')
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'lib'))

# Drop any mock module a prior test may have inserted (other test modules stub
# bisect_utils / repo_manager); we want the real ones here.
for stale in ('repo_manager', 'bisect_utils', 'log_config'):
    sys.modules.pop(stale, None)

from repo_manager import SharedRepoManager


class TestCleanupTaskWorkspace(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.manager = SharedRepoManager.__new__(SharedRepoManager)
        self.manager.REPO_BASE_DIR = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def test_removes_existing_task_workspace(self):
        task_id = '999'
        workspace = os.path.join(self.manager.REPO_BASE_DIR, task_id)
        os.makedirs(os.path.join(workspace, 'kernel', '.git'), exist_ok=True)
        with open(os.path.join(workspace, 'kernel', 'README'), 'w') as f:
            f.write('content')

        result = self.manager.cleanup_task_workspace(task_id)

        self.assertTrue(result)
        self.assertFalse(os.path.exists(workspace))

    def test_returns_false_when_workspace_missing(self):
        result = self.manager.cleanup_task_workspace('does-not-exist')
        self.assertFalse(result)

    def test_accepts_integer_task_id(self):
        task_id = 12345
        workspace = os.path.join(self.manager.REPO_BASE_DIR, str(task_id))
        os.makedirs(workspace, exist_ok=True)

        result = self.manager.cleanup_task_workspace(task_id)

        self.assertTrue(result)
        self.assertFalse(os.path.exists(workspace))


if __name__ == '__main__':
    unittest.main()
