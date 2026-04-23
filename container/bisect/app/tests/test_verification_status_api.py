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
    BISECT_METRICS_PRODUCER_ENABLED = True
    BISECT_ERROR_PRODUCER_ENABLED = True
    BISECT_KERNEL_CI_PRODUCER_ENABLED = True
    PERFORMANCE_PRODUCER_ENABLED = True
    BISECT_CONSUMER_ENABLED = True
    BISECT_CONSUMER_STARTUP_DELAY_SECONDS = 300


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
    active_task_locks=set(),
    get_consumer_gate_state=MagicMock(return_value={
        'configured_enabled': True,
        'accepting_new_tasks': True,
        'pause_reason': None,
        'startup_delay_seconds': 300,
        'startup_delay_remaining_seconds': 0,
    }),
    get_producer_gate_state=MagicMock(return_value={
        'configured_enabled': True,
        'accepting_new_cycles': True,
        'pause_reason': None,
        'configured_producers': ['metrics', 'kernel_ci', 'error', 'performance'],
        'effective_producers': ['metrics', 'kernel_ci', 'error', 'performance'],
        'producers': {
            'metrics': {'configured_enabled': True},
            'kernel_ci': {'configured_enabled': True},
            'error': {'configured_enabled': True},
            'performance': {'configured_enabled': True},
        },
    }),
    normalize_producer_target=MagicMock(side_effect=lambda target: (target or 'all')),
    set_producer_enabled=MagicMock(return_value=True),
    wake_producer_control_worker=MagicMock(),
    wake_consumer_control_workers=MagicMock(),
    handle_deleted_tasks=MagicMock(return_value={'runtime_marked': 0, 'cancelled': 0}),
)
sys.modules['services.pool_monitor_service'].PoolMonitorService = MagicMock

os.environ.setdefault('CCI_SRC', '/tmp')
os.environ.setdefault('LKP_SRC', '/tmp')

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO_ROOT, 'container', 'bisect', 'app'))

import controllers


class TestVerificationStatusApi(unittest.TestCase):

    def setUp(self):
        controllers.Config.BISECT_CONSUMER_ENABLED = True
        controllers.bisect_task_instance.active_task_locks = set()
        controllers.bisect_task_instance.get_consumer_gate_state = MagicMock(return_value={
            'configured_enabled': True,
            'accepting_new_tasks': True,
            'pause_reason': None,
            'startup_delay_seconds': 300,
            'startup_delay_remaining_seconds': 0,
        })
        controllers.bisect_task_instance.get_producer_gate_state = MagicMock(return_value={
            'configured_enabled': True,
            'accepting_new_cycles': True,
            'pause_reason': None,
            'configured_producers': ['metrics', 'kernel_ci', 'error', 'performance'],
            'effective_producers': ['metrics', 'kernel_ci', 'error', 'performance'],
            'producers': {
                'metrics': {'configured_enabled': True},
                'kernel_ci': {'configured_enabled': True},
                'error': {'configured_enabled': True},
                'performance': {'configured_enabled': True},
            },
        })
        controllers.bisect_task_instance.normalize_producer_target = MagicMock(
            side_effect=lambda target: (target or 'all')
        )
        controllers.bisect_task_instance.set_producer_enabled = MagicMock(return_value=True)
        controllers.bisect_task_instance.wake_producer_control_worker = MagicMock()
        controllers.bisect_task_instance.wake_consumer_control_workers = MagicMock()
        controllers.bisect_task_instance.handle_deleted_tasks = MagicMock(
            return_value={'runtime_marked': 0, 'cancelled': 0}
        )

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

    def test_task_status_overview_uses_pending_verification(self):
        counts = {
            "bisect_status = 'success'": 3,
            "bisect_status = 'failed'": 1,
            "bisect_status = 'processing'": 2,
            "bisect_status = 'verifying'": 4,
            "bisect_status = 'wait'": 5,
            "bisect_status = 'pending_verification'": 6,
            "category = 'build' AND bisect_status = 'success'": 1,
            "category = 'build' AND bisect_status = 'failed'": 1,
            "category = 'build' AND bisect_status = 'processing'": 0,
            "category = 'build' AND bisect_status = 'verifying'": 0,
            "category = 'build' AND bisect_status = 'wait'": 2,
            "category = 'build' AND bisect_status = 'pending_verification'": 1,
            "category = 'benchmark' AND bisect_status = 'success'": 1,
            "category = 'benchmark' AND bisect_status = 'failed'": 0,
            "category = 'benchmark' AND bisect_status = 'processing'": 1,
            "category = 'benchmark' AND bisect_status = 'verifying'": 2,
            "category = 'benchmark' AND bisect_status = 'wait'": 2,
            "category = 'benchmark' AND bisect_status = 'pending_verification'": 3,
            "category = 'function' AND bisect_status = 'success'": 1,
            "category = 'function' AND bisect_status = 'failed'": 0,
            "category = 'function' AND bisect_status = 'processing'": 1,
            "category = 'function' AND bisect_status = 'verifying'": 2,
            "category = 'function' AND bisect_status = 'wait'": 1,
            "category = 'function' AND bisect_status = 'pending_verification'": 2,
        }

        with patch.object(controllers, '_select_count', side_effect=lambda _client, where: counts.get(where, 0)):
            overview = controllers._get_task_status_overview(MagicMock())

        self.assertEqual(
            overview['statuses'],
            ['success', 'failed', 'processing', 'verifying', 'wait', 'pending_verification']
        )
        self.assertEqual(overview['task_status_counts']['pending_verification'], 6)
        self.assertEqual(overview['task_total'], 21)
        self.assertEqual(overview['category_status_counts']['benchmark']['pending_verification'], 3)

    def test_get_status_overview_returns_json(self):
        app = Flask(__name__)
        expected = {'task_status_counts': {'pending_verification': 6}, 'task_total': 21}

        with app.app_context():
            with patch.object(controllers, '_get_task_status_overview', return_value=expected):
                response, status_code = controllers.get_status_overview()

        self.assertEqual(status_code, 200)
        self.assertEqual(response.get_json(), expected)

    def test_toggle_consumer_returns_gate_snapshot(self):
        app = Flask(__name__)
        controllers.bisect_task_instance.get_consumer_gate_state = MagicMock(return_value={
            'configured_enabled': False,
            'accepting_new_tasks': False,
            'pause_reason': 'disabled',
            'startup_delay_seconds': 300,
            'startup_delay_remaining_seconds': 12,
        })

        with app.test_request_context('/toggle_consumer?state=disable'):
            response, status_code = controllers.toggle_consumer()

        body = response.get_json()
        self.assertEqual(status_code, 200)
        self.assertFalse(body['consumer_enabled'])
        self.assertFalse(body['accepting_new_tasks'])
        self.assertEqual(body['pause_reason'], 'disabled')
        self.assertEqual(body['startup_delay_remaining_seconds'], 12)
        controllers.bisect_task_instance.wake_consumer_control_workers.assert_called_once_with()

    def test_toggle_producer_returns_gate_snapshot(self):
        app = Flask(__name__)
        controllers.bisect_task_instance.set_producer_enabled = MagicMock(return_value=True)
        controllers.bisect_task_instance.get_producer_gate_state = MagicMock(return_value={
            'configured_enabled': True,
            'accepting_new_cycles': True,
            'pause_reason': None,
            'configured_producers': ['metrics', 'error', 'performance'],
            'effective_producers': ['metrics', 'error', 'performance'],
            'producers': {
                'metrics': {'configured_enabled': True},
                'kernel_ci': {'configured_enabled': False},
                'error': {'configured_enabled': True},
                'performance': {'configured_enabled': True},
            },
        })

        with app.test_request_context('/toggle_producer?state=disable&producer=kernel_ci'):
            response, status_code = controllers.toggle_producer()

        body = response.get_json()
        self.assertEqual(status_code, 200)
        self.assertEqual(body['target'], 'kernel_ci')
        self.assertTrue(body['producer_enabled'])
        self.assertTrue(body['accepting_new_cycles'])
        self.assertIsNone(body['pause_reason'])
        self.assertFalse(body['component_enabled'])
        self.assertEqual(body['action'], 'configuration updated')
        controllers.bisect_task_instance.set_producer_enabled.assert_called_once_with('kernel_ci', False)
        controllers.bisect_task_instance.wake_producer_control_worker.assert_called_once_with()

    def test_get_consumer_status_includes_startup_delay(self):
        app = Flask(__name__)
        controllers.bisect_task_instance.active_task_locks = {'11', '12'}
        controllers.bisect_task_instance.get_consumer_gate_state = MagicMock(return_value={
            'configured_enabled': True,
            'accepting_new_tasks': False,
            'pause_reason': 'startup_delay',
            'startup_delay_seconds': 300,
            'startup_delay_remaining_seconds': 45,
        })

        original_enumerate = controllers.threading.enumerate

        def fake_enumerate():
            extra_threads = [
                types.SimpleNamespace(name='SuccessTaskValidator', is_alive=lambda: True, daemon=True),
                types.SimpleNamespace(name='BisectConsumer', is_alive=lambda: True, daemon=True),
            ]
            return extra_threads + list(original_enumerate())

        with app.app_context():
            with patch.object(controllers.threading, 'enumerate', side_effect=fake_enumerate):
                response, status_code = controllers.get_consumer_status()

        body = response.get_json()
        self.assertEqual(status_code, 200)
        self.assertFalse(body['accepting_new_tasks'])
        self.assertEqual(body['pause_reason'], 'startup_delay')
        self.assertEqual(body['startup_delay_remaining_seconds'], 45)
        self.assertEqual(body['active_task_locks'], 2)
        self.assertEqual(
            [item['name'] for item in body['worker_threads']],
            ['BisectConsumer', 'SuccessTaskValidator']
        )

    def test_get_producer_status_includes_pause_reason(self):
        app = Flask(__name__)
        controllers.bisect_task_instance.get_producer_gate_state = MagicMock(return_value={
            'configured_enabled': False,
            'accepting_new_cycles': False,
            'pause_reason': 'disabled',
            'configured_producers': ['metrics', 'error'],
            'effective_producers': [],
            'producers': {
                'metrics': {'configured_enabled': True},
                'kernel_ci': {'configured_enabled': False},
                'error': {'configured_enabled': True},
                'performance': {'configured_enabled': False},
            },
        })

        original_enumerate = controllers.threading.enumerate

        def fake_enumerate():
            extra_threads = [
                types.SimpleNamespace(
                    name='BisectProducer',
                    _target=types.SimpleNamespace(__name__='bisect_producer'),
                    is_alive=lambda: True,
                    daemon=True,
                ),
            ]
            return extra_threads + list(original_enumerate())

        with app.app_context():
            with patch.object(controllers.threading, 'enumerate', side_effect=fake_enumerate):
                response, status_code = controllers.get_producer_status()

        body = response.get_json()
        self.assertEqual(status_code, 200)
        self.assertFalse(body['producer_enabled'])
        self.assertFalse(body['accepting_new_cycles'])
        self.assertEqual(body['pause_reason'], 'disabled')
        self.assertEqual(body['effective_producers'], [])
        self.assertEqual(body['active_producer_threads'], 1)

    def test_delete_tasks_reconciles_runtime_state(self):
        app = Flask(__name__)
        client = MagicMock()
        client.sql_select.return_value = [{'id': '11'}, {'id': 12}]
        client.sql_raw.return_value = [{'total': 2, 'error': ''}]
        controllers.bisect_task_instance.handle_deleted_tasks = MagicMock(
            return_value={'runtime_marked': 2, 'cancelled': 1}
        )

        with app.test_request_context('/delete_tasks?status=wait', method='DELETE'):
            with patch.object(controllers, '_get_manticore_client', return_value=client), \
                 patch.object(controllers, 'build_task_query_conditions', return_value=("bisect_status = 'wait'", {'status': 'wait'})), \
                 patch.object(controllers, 'build_condition_summary', return_value='status=wait'):
                response, status_code = controllers.delete_tasks_by_condition()

        body = response.get_json()
        self.assertEqual(status_code, 200)
        self.assertEqual(body['deleted_count'], 2)
        self.assertEqual(body['runtime_reconciled'], {'runtime_marked': 2, 'cancelled': 1})
        controllers.bisect_task_instance.handle_deleted_tasks.assert_called_once_with([11, 12])
        client.sql_raw.assert_called_once_with("DELETE FROM bisect WHERE bisect_status = 'wait'")

    def test_delete_tasks_without_matches_skips_runtime_reconciliation(self):
        app = Flask(__name__)
        client = MagicMock()
        client.sql_select.return_value = []

        with app.test_request_context('/delete_tasks?status=wait', method='DELETE'):
            with patch.object(controllers, '_get_manticore_client', return_value=client), \
                 patch.object(controllers, 'build_task_query_conditions', return_value=("bisect_status = 'wait'", {'status': 'wait'})):
                response, status_code = controllers.delete_tasks_by_condition()

        body = response.get_json()
        self.assertEqual(status_code, 200)
        self.assertEqual(body['deleted_count'], 0)
        self.assertEqual(body['runtime_reconciled'], {'runtime_marked': 0, 'cancelled': 0})
        controllers.bisect_task_instance.handle_deleted_tasks.assert_not_called()
        client.sql_raw.assert_not_called()


if __name__ == '__main__':
    unittest.main()
