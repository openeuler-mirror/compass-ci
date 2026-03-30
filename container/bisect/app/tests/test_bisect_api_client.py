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

    def test_main_dispatches_verification_status_command(self):
        with patch('sbin.bisect_api.BisectAPIClient') as mock_client_cls:
            mock_client = mock_client_cls.return_value
            mock_client.verification_status = MagicMock()

            with patch.object(sys, 'argv', ['bisect_api.py', 'verification_status']):
                main()

        mock_client.verification_status.assert_called_once_with()

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
