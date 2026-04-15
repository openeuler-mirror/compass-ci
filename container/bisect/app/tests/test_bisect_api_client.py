#!/usr/bin/env python3
"""Tests for the bisect_api.py client helpers."""

import os
import sys
import unittest
from unittest.mock import MagicMock, patch


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, REPO_ROOT)

from sbin.bisect_api import BisectAPIClient, main


class TestBisectApiClient(unittest.TestCase):

    def test_verification_status_calls_expected_endpoint(self):
        client = BisectAPIClient(host='example.com')
        client._make_request = MagicMock(return_value={'ok': True})

        result = client.verification_status()

        self.assertEqual(result, {'ok': True})
        client._make_request.assert_called_once_with("GET", "/verification_status")

    def test_toggle_consumer_calls_expected_endpoint(self):
        client = BisectAPIClient(host='example.com')
        client._make_request = MagicMock(return_value={'ok': True})

        result = client.toggle_consumer(False)

        self.assertEqual(result, {'ok': True})
        client._make_request.assert_called_once_with("POST", "/toggle_consumer?state=disable")

    def test_consumer_status_calls_expected_endpoint(self):
        client = BisectAPIClient(host='example.com')
        client._make_request = MagicMock(return_value={'ok': True})

        result = client.consumer_status()

        self.assertEqual(result, {'ok': True})
        client._make_request.assert_called_once_with("GET", "/consumer_status")

    def test_status_uses_status_overview_and_runtime_endpoints(self):
        client = BisectAPIClient(host='example.com')
        client._make_silent_request = MagicMock(side_effect=[
            {
                'statuses': ['success', 'failed', 'processing', 'verifying', 'wait', 'pending_verification'],
                'categories': ['build', 'benchmark', 'function'],
                'task_status_counts': {
                    'success': 5,
                    'failed': 2,
                    'processing': 1,
                    'verifying': 3,
                    'wait': 4,
                    'pending_verification': 6,
                },
                'task_total': 21,
                'category_status_counts': {
                    'build': {'success': 2, 'failed': 1, 'processing': 0, 'verifying': 0, 'wait': 1, 'pending_verification': 1},
                    'benchmark': {'success': 2, 'failed': 1, 'processing': 1, 'verifying': 2, 'wait': 2, 'pending_verification': 3},
                    'function': {'success': 1, 'failed': 0, 'processing': 0, 'verifying': 1, 'wait': 1, 'pending_verification': 2},
                },
            },
            {
                'verifying': 3,
                'pending_verification': 6,
                'verification_status_counts': {'verified': 9},
                'config': {'max_verifying_tasks': 10, 'verification_timeout_hours': 24},
            },
            {'active_threads': 4, 'max_workers': 8, 'pending_tasks': 2},
            {'producer_enabled': True, 'producer_threads': [{'is_alive': True}]},
            {
                'consumer_enabled': True,
                'accepting_new_tasks': False,
                'pause_reason': 'startup_delay',
                'startup_delay_remaining_seconds': 45,
            },
        ])

        with patch('builtins.print') as mock_print, \
             patch.object(client, '_print_scheduler_status') as mock_sched, \
             patch.object(client, '_print_job_completion_trend') as mock_trend:
            result = client.status()

        self.assertEqual(result['task_total'], 21)
        self.assertEqual(client._make_silent_request.call_args_list[0].args, ('GET', '/status_overview'))
        self.assertEqual(client._make_silent_request.call_args_list[4].args, ('GET', '/consumer_status'))
        output = '\n'.join(str(call.args[0]) for call in mock_print.call_args_list if call.args)
        self.assertIn('pending_verification', output)
        self.assertIn('Consumer:', output)
        mock_sched.assert_called_once_with()
        mock_trend.assert_called_once_with()

    def test_main_dispatches_verification_status_command(self):
        with patch('sbin.bisect_api.BisectAPIClient') as mock_client_cls:
            mock_client = mock_client_cls.return_value
            mock_client.verification_status = MagicMock()

            with patch.object(sys, 'argv', ['bisect_api.py', 'verification_status']):
                main()

        mock_client.verification_status.assert_called_once_with()

    def test_main_dispatches_enable_consumer_command(self):
        with patch('sbin.bisect_api.BisectAPIClient') as mock_client_cls:
            mock_client = mock_client_cls.return_value
            mock_client.toggle_consumer = MagicMock()

            with patch.object(sys, 'argv', ['bisect_api.py', 'enable_consumer']):
                main()

        mock_client.toggle_consumer.assert_called_once_with(True)

    def test_main_dispatches_consumer_status_command(self):
        with patch('sbin.bisect_api.BisectAPIClient') as mock_client_cls:
            mock_client = mock_client_cls.return_value
            mock_client.consumer_status = MagicMock()

            with patch.object(sys, 'argv', ['bisect_api.py', 'consumer_status']):
                main()

        mock_client.consumer_status.assert_called_once_with()

    def test_main_dispatches_status_command(self):
        with patch('sbin.bisect_api.BisectAPIClient') as mock_client_cls:
            mock_client = mock_client_cls.return_value
            mock_client.status = MagicMock()

            with patch.object(sys, 'argv', ['bisect_api.py', 'status']):
                main()

        mock_client.status.assert_called_once_with()

    def test_main_list_tasks_maps_id_to_task_id(self):
        with patch('sbin.bisect_api.BisectAPIClient') as mock_client_cls:
            mock_client = mock_client_cls.return_value
            mock_client.list_tasks = MagicMock()

            with patch.object(sys, 'argv', ['bisect_api.py', 'list_tasks', '--id', '123']):
                main()

        mock_client.list_tasks.assert_called_once_with(
            status=None,
            error_id=None,
            bad_job_id=None,
            category=None,
            hours=None,
            git_url=None,
            task_id='123',
            task_ids=None,
            commit=None,
            limit=None
        )

    def test_main_reset_failed_passes_yes_flag(self):
        with patch('sbin.bisect_api.BisectAPIClient') as mock_client_cls:
            mock_client = mock_client_cls.return_value
            mock_client.reset_failed_tasks = MagicMock()

            with patch.object(sys, 'argv', ['bisect_api.py', 'reset_failed', '--yes']):
                main()

        mock_client.reset_failed_tasks.assert_called_once_with(assume_yes=True)

    def test_reset_failed_non_interactive_without_yes_does_not_call_api(self):
        client = BisectAPIClient(host='example.com')
        client._make_request = MagicMock()

        with patch('builtins.input', side_effect=EOFError):
            result = client.reset_failed_tasks()

        self.assertIsNone(result)
        client._make_request.assert_not_called()


if __name__ == '__main__':
    unittest.main()
