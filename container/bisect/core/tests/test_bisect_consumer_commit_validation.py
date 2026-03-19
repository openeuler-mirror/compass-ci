#!/usr/bin/env python3
"""Tests for commit reference validation in BisectConsumer."""

import os
import sys
import types
import unittest
from unittest.mock import MagicMock


# Stub external dependencies before importing target module.
for mod_name in [
    'lkp_bisect', 'lkp_bisect.db', 'lkp_bisect.db.manticore',
    'lkp_bisect.core', 'lkp_bisect.core.git_bisect',
    'log_config', 'bisect_utils', 'notification_writer',
]:
    if mod_name not in sys.modules:
        sys.modules[mod_name] = types.ModuleType(mod_name)

sys.modules['lkp_bisect.db.manticore'].ManticoreClient = MagicMock
sys.modules['lkp_bisect.core.git_bisect'].GitBisect = MagicMock
sys.modules['log_config'].logger = MagicMock()
sys.modules['log_config'].StructuredLogger = MagicMock
sys.modules['bisect_utils'].extract_repo_name_from_url = MagicMock(return_value='repo')
sys.modules['notification_writer'].NotificationWriter = MagicMock

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO_ROOT, 'container', 'bisect', 'core'))

from bisect_consumer import BisectConsumer


class TestBisectConsumerCommitValidation(unittest.TestCase):

    def _make_consumer(self):
        c = BisectConsumer.__new__(BisectConsumer)
        c.client = MagicMock()
        c.config = {}
        return c

    def test_rejects_placeholder_good_commit(self):
        consumer = self._make_consumer()
        data = {
            'id': 1,
            'bad_job_id': 'job1',
            'error_id': 'err',
            'good_commit': 'N/A',
        }
        result = consumer._validate_task_data(data)
        self.assertIn('error', result)
        self.assertIn('Invalid good commit reference', result['error'])

    def test_accepts_normal_commit_ref(self):
        consumer = self._make_consumer()
        data = {
            'id': 2,
            'bad_job_id': 'job2',
            'error_id': 'err',
            'good_commit': '9ce4f8e56bd2',
        }
        result = consumer._validate_task_data(data)
        self.assertNotIn('error', result)


if __name__ == '__main__':
    unittest.main()
