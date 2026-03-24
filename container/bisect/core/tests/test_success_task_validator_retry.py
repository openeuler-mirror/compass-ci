#!/usr/bin/env python3
"""Tests for retry/backoff behavior in SuccessTaskValidator."""

import os
import sys
import types
import unittest
from unittest.mock import MagicMock, patch


# Stub external dependencies before importing target module.
for mod_name in [
    'lkp_bisect', 'lkp_bisect.db', 'lkp_bisect.db.manticore',
    'lkp_bisect.core', 'lkp_bisect.core.git_bisect',
    'verification_consumer', 'errid_intelligence', 'bisect_utils', 'log_config',
]:
    if mod_name not in sys.modules:
        sys.modules[mod_name] = types.ModuleType(mod_name)

sys.modules['lkp_bisect.db.manticore'].ManticoreClient = MagicMock
sys.modules['lkp_bisect.core.git_bisect'].GitBisect = MagicMock
sys.modules['verification_consumer'].VerificationConsumer = object
sys.modules['errid_intelligence'].ErridIntelligence = MagicMock
sys.modules['log_config'].logger = MagicMock()
sys.modules['bisect_utils'].write_regression_record = MagicMock(return_value=True)
sys.modules['bisect_utils'].mark_similar_wait_tasks_for_verification = MagicMock()
sys.modules['bisect_utils'].mark_introduced_errid_tasks_for_verification = MagicMock()

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO_ROOT, 'container', 'bisect', 'validators'))

from success_task_validator import SuccessTaskValidator


class TestSuccessTaskValidatorRetry(unittest.TestCase):

    def _make_validator(self):
        v = SuccessTaskValidator.__new__(SuccessTaskValidator)
        v.client = MagicMock()
        v.bisect_instance = MagicMock()
        v.commit_time_client = MagicMock()
        v.validation_batch_size = 200
        return v

    def test_terminal_health_helper_matches_constants_categories(self):
        validator = self._make_validator()
        self.assertTrue(validator._is_terminal_failed_health('abort_provider'))
        self.assertTrue(validator._is_terminal_failed_health('timeout_setup'))
        self.assertTrue(validator._is_terminal_failed_health('cancel'))
        self.assertFalse(validator._is_terminal_failed_health('success'))

    def test_submit_returns_retry_when_parent_commit_api_unavailable(self):
        validator = self._make_validator()
        validator.commit_time_client.get_parent_commit.return_value = None

        result = validator._submit_verification_jobs_with_shared_repo(
            task_id=123,
            bad_job_id='job1',
            first_bad_commit='9ce4f8e56bd2',
            git_url='https://example.com/repo.git',
            error_id='eid',
            repo_dir=''
        )

        self.assertEqual(result.get('status'), 'retry')
        self.assertIn('failed_to_get_parent_commit_via_api', result.get('error', ''))

    @patch('success_task_validator.time.time', return_value=1_000)
    def test_schedule_retry_sets_backoff_fields(self, _mock_time):
        validator = self._make_validator()
        validator.client.sql_select.return_value = [{
            'j': {
                'verification_submit_retry_count': 1,
                'verification_jobs': {'status': 'retry_pending'}
            }
        }]

        validator._schedule_verification_retry(
            task_id=123,
            related_task_id='456',
            reason='failed_to_get_parent_commit_via_api: commit=9ce4f8e56bd2'
        )

        args = validator.client.update.call_args[0]
        self.assertEqual(args[0], 'bisect')
        self.assertEqual(args[1], 123)
        doc = args[2]
        self.assertEqual(doc['bisect_status'], 'verifying')
        self.assertEqual(doc['j']['verification_submit_retry_count'], 2)
        self.assertEqual(doc['j']['verification_submit_last_retry_at'], 1000)
        # retry_count=2 -> backoff=600s
        self.assertEqual(doc['j']['verification_submit_next_retry_at'], 1600)

    def test_batch_submit_marks_repo_mismatch_failed(self):
        validator = self._make_validator()
        validator.client.sql_select.return_value = [{
            'id': 456,
            'bisect_status': 'success',
            'first_bad_commit': '9ce4f8e56bd2',
            'git_url': 'https://example.com/other.git',
        }]
        validator._mark_task_failed = MagicMock()
        validator._submit_verification_jobs_with_shared_repo = MagicMock()

        stats = validator.batch_submit_verification_jobs(
            repo_tasks=[{
                'id': 123,
                'bad_job_id': 'job1',
                'error_id': 'eid',
                'j': {'related_task_id': '456'},
            }],
            git_url='https://example.com/repo.git',
        )

        self.assertEqual(stats['submitted'], 0)
        self.assertEqual(stats['failed'], 1)
        validator._mark_task_failed.assert_called_once()
        reason = validator._mark_task_failed.call_args[0][2]
        self.assertIn('related_task_repo_mismatch', reason)
        validator._submit_verification_jobs_with_shared_repo.assert_not_called()

    @patch('success_task_validator.time.time', return_value=1_000)
    def test_scan_unverified_tasks_skips_retry_backoff_window(self, _mock_time):
        validator = self._make_validator()
        validator.client.sql_select.return_value = [{
            'id': 123,
            'bad_job_id': 'job1',
            'error_id': 'eid',
            'bisect_status': 'verifying',
            'git_url': 'https://example.com/repo.git',
            'updated_at': 900,
            'submit_time': 900,
            'j': {
                'related_task_id': '456',
                'verification_status': 'retry_pending',
                'verification_jobs': {
                    'status': 'retry_pending',
                    'next_retry_at': 1300,
                }
            }
        }]
        validator._reset_tasks_to_wait = MagicMock()

        tasks = validator.scan_unverified_tasks()

        self.assertEqual(tasks, [])
        validator._reset_tasks_to_wait.assert_not_called()

    @patch('success_task_validator.time.time', return_value=2_000)
    def test_check_results_marks_timeout_for_abort_health(self, _mock_time):
        validator = self._make_validator()
        validator.client.sql_select.return_value = [{
            'id': 123,
            'bisect_status': 'verifying',
            'updated_at': 1_900,
            'j': {
                'verification_jobs': {
                    'parent_job_id': 'p1',
                    'candidate_job_id': 'c1',
                    'parent_result_root': '/tmp/p1',
                    'candidate_result_root': '/tmp/c1',
                    'submit_time': 1_900,
                }
            }
        }]
        validator.bisect_instance._poll_job_stats.side_effect = [
            (None, 'abort'),
            (None, 'success'),
        ]
        validator.mark_verification_timeout = MagicMock()

        stats = validator.check_verification_results_once(limit=10, timeout_hours=24)

        self.assertEqual(stats['checked'], 1)
        self.assertEqual(stats['timeout'], 1)
        validator.mark_verification_timeout.assert_called_once()
        reason = validator.mark_verification_timeout.call_args.kwargs.get('reason', '')
        self.assertIn('terminal_job_health', reason)

    @patch('success_task_validator.time.time', return_value=2_000)
    def test_check_results_marks_timeout_for_timeout_boot_health(self, _mock_time):
        validator = self._make_validator()
        validator.client.sql_select.return_value = [{
            'id': 456,
            'bisect_status': 'verifying',
            'updated_at': 1_900,
            'j': {
                'verification_jobs': {
                    'parent_job_id': 'p2',
                    'candidate_job_id': 'c2',
                    'parent_result_root': '/tmp/p2',
                    'candidate_result_root': '/tmp/c2',
                    'submit_time': 1_900,
                }
            }
        }]
        validator.bisect_instance._poll_job_stats.side_effect = [
            (None, 'success'),
            (None, 'timeout_boot'),
        ]
        validator.mark_verification_timeout = MagicMock()

        stats = validator.check_verification_results_once(limit=10, timeout_hours=24)

        self.assertEqual(stats['checked'], 1)
        self.assertEqual(stats['timeout'], 1)
        validator.mark_verification_timeout.assert_called_once()
        reason = validator.mark_verification_timeout.call_args.kwargs.get('reason', '')
        self.assertIn('terminal_job_health', reason)


if __name__ == '__main__':
    unittest.main()
