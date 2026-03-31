#!/usr/bin/env python3
"""Tests for verification queue status API helpers."""

import os
import sys
import types
import unittest
from unittest.mock import MagicMock, patch

from flask import Flask


for mod_name in [
    'config',
    'log_config',
    'query_builder',
    'lkp_bisect', 'lkp_bisect.core', 'lkp_bisect.core.git_bisect',
    'lkp_bisect.db', 'lkp_bisect.db.manticore',
    'task_processor',
    'services',
    'services.pool_monitor_service',
]:
    if mod_name not in sys.modules:
        sys.modules[mod_name] = types.ModuleType(mod_name)


class _DummyConfig:
    MAX_VERIFYING_TASKS = 10
    VERIFICATION_TIMEOUT_HOURS = 24
    VERIFICATION_TIMEOUT_RETRY_MAX = 2
    VERIFICATION_TIMEOUT_FINAL_ACTION = 'rebisect'
    DEFAULT_QUERY_LIMIT = 20
    MAX_QUERY_LIMIT = 200
    BISECT_PRODUCER_ENABLED = True


sys.modules['config'].Config = _DummyConfig()
sys.modules['log_config'].logger = MagicMock()
sys.modules['query_builder'].build_task_query_conditions = MagicMock(return_value=("1=1", {}))
sys.modules['query_builder'].build_condition_summary = MagicMock(return_value="")
sys.modules['query_builder']._escape_sql_string = MagicMock(side_effect=lambda x: x)
sys.modules['lkp_bisect.core.git_bisect'].GitBisect = MagicMock
sys.modules['lkp_bisect.db.manticore'].ManticoreClient = MagicMock
sys.modules['task_processor'].bisect_task_instance = types.SimpleNamespace(
    _config={
        'max_verifying_tasks': 7,
        'verification_timeout_hours': 36,
        'verification_timeout_retry_max': 4,
        'verification_timeout_final_action': 'rebisect',
    },
    thread_pool=types.SimpleNamespace(
        _max_workers=4,
        _work_queue=types.SimpleNamespace(qsize=lambda: 1, _tasks_done=3),
    ),
)
sys.modules['services.pool_monitor_service'].PoolMonitorService = MagicMock

os.environ.setdefault('CCI_SRC', '/tmp')
os.environ.setdefault('LKP_SRC', '/tmp')

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO_ROOT, 'container', 'bisect', 'app'))

import controllers


class TestVerificationStatusApi(unittest.TestCase):

    def test_snapshot_counts_queue_pressure(self):
        client = MagicMock()
        client.sql_select.side_effect = [
            [{'count': 5}],
            [{'count': 3}],
            [{'count': 2}],
            [{'count': 1}],
            [{'count': 4}],
            [{'count': 0}],
            [{'count': 9}],
        ]

        snapshot = controllers._get_verification_queue_snapshot(client)

        self.assertEqual(snapshot['pending_verification'], 5)
        self.assertEqual(snapshot['verifying'], 3)
        self.assertEqual(snapshot['active_submitted_verifying'], 2)
        self.assertEqual(snapshot['available_verifying_slots'], 5)
        self.assertEqual(snapshot['verification_status_counts']['timeout_retry_pending'], 1)
        self.assertEqual(snapshot['verification_status_counts']['timeout'], 4)
        self.assertEqual(snapshot['verification_status_counts']['verified'], 9)
        self.assertEqual(snapshot['config']['verification_timeout_hours'], 36)

    def test_get_verification_status_returns_json(self):
        app = Flask(__name__)
        expected = {'pending_verification': 2, 'verifying': 1}

        with app.app_context():
            with patch.object(controllers, '_get_verification_queue_snapshot', return_value=expected):
                response, status_code = controllers.get_verification_status()

        self.assertEqual(status_code, 200)
        self.assertEqual(response.get_json(), expected)


if __name__ == '__main__':
    unittest.main()
