#!/usr/bin/env python3
"""Focused tests for HeadValidator main flow helpers."""

import os
import sys
import types
import unittest
from unittest.mock import MagicMock, patch


for mod_name in [
    'lkp_bisect', 'lkp_bisect.db', 'lkp_bisect.db.manticore',
    'lkp_bisect.core', 'lkp_bisect.core.git_bisect',
    'lkp_bisect.notify', 'lkp_bisect.notify.feishu',
    'verification_consumer', 'repo_manager', 'bisect_utils', 'log_config',
]:
    if mod_name not in sys.modules:
        sys.modules[mod_name] = types.ModuleType(mod_name)

sys.modules['lkp_bisect.db.manticore'].ManticoreClient = MagicMock
sys.modules['lkp_bisect.core.git_bisect'].GitBisect = MagicMock
sys.modules['lkp_bisect.notify.feishu'].FeishuNotifier = MagicMock
sys.modules['verification_consumer'].VerificationConsumer = object
sys.modules['repo_manager'].SharedRepoManager = MagicMock
sys.modules['bisect_utils'].extract_repo_name_from_url = MagicMock(return_value='repo')
sys.modules['log_config'].logger = MagicMock()

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO_ROOT, 'container', 'bisect', 'validators'))
os.environ.setdefault('CCI_SRC', '/tmp')
os.environ.setdefault('LKP_SRC', '/tmp')

sys.modules.pop('head_validator', None)
from head_validator import HeadValidator


class TestHeadValidatorFlow(unittest.TestCase):

    def _make_validator(self):
        validator = HeadValidator.__new__(HeadValidator)
        validator.client = MagicMock()
        validator.bisect_instance = MagicMock()
        validator.check_batch_size = 10
        validator.check_interval = 86400
        validator.notification_webhook = ''
        validator.notification_email = ''
        validator.notification_writer = MagicMock()
        validator._feishu = None
        validator._get_repo_dir = MagicMock(return_value=('/repo', '/job'))
        validator._release_repo_to_pool = MagicMock()
        return validator

    def test_scan_verified_tasks_uses_limit_and_interval_threshold(self):
        validator = self._make_validator()
        validator.client.sql_select.return_value = [{'id': 1}]

        with patch('head_validator.time.time', return_value=200000):
            tasks = validator.scan_verified_tasks(limit=7)

        self.assertEqual(tasks, [{'id': 1}])
        sql = validator.client.sql_select.call_args[0][0]
        self.assertIn("j.verification_status = 'verified'", sql)
        self.assertIn("j.head_check_completed IS NULL OR j.head_check_completed = 0", sql)
        self.assertIn("j.head_check_at IS NULL", sql)
        self.assertIn("j.head_check_at < 113600", sql)
        self.assertIn("LIMIT 7", sql)

    def test_update_head_check_status_merges_existing_j_fields(self):
        validator = self._make_validator()
        validator.client.sql_select_one.return_value = {
            'j': {
                'verification_status': 'verified',
                'introduced_errids': ['eid.a'],
                'keep_me': 'yes',
            }
        }
        validator.client.update.return_value = True

        with patch('head_validator.time.time', return_value=300000):
            validator.update_head_check_status(
                task_id=12,
                status='regressed',
                head_commit='abc123',
                head_job_id='job-1',
                regressed_errids=['eid.a'],
                verified=False,
                status_changed=True,
            )

        validator.client.update.assert_called_once()
        args = validator.client.update.call_args[0]
        self.assertEqual(args[0], 'bisect')
        self.assertEqual(args[1], 12)
        update_doc = args[2]
        self.assertEqual(update_doc['updated_at'], 300000)
        self.assertEqual(update_doc['j']['verification_status'], 'verified')
        self.assertEqual(update_doc['j']['keep_me'], 'yes')
        self.assertEqual(update_doc['j']['head_check_status'], 'regressed')
        self.assertEqual(update_doc['j']['head_check_commit'], 'abc123')
        self.assertEqual(update_doc['j']['head_check_job_id'], 'job-1')
        self.assertEqual(update_doc['j']['head_check_verified'], False)
        self.assertEqual(update_doc['j']['head_check_status_changed'], True)
        self.assertEqual(update_doc['j']['regressed_errids'], ['eid.a'])

    def test_finalize_head_check_regressed_updates_task_and_notifies(self):
        validator = self._make_validator()
        validator.bisect_instance._poll_job_stats.return_value = ({'eid.a': 1, 'other': 1}, 'success')
        validator.client.update.return_value = True
        validator.trigger_notification = MagicMock()
        task = {'id': 101, 'j': {'introduced_errids': ['eid.a', 'eid.b'], 'keep_me': 'yes'}}

        with patch('head_validator.time.time', return_value=123456):
            status = validator._finalize_head_check(task, 'job-1', 'head-commit', ['eid.a', 'eid.b'])

        self.assertEqual(status, 'regressed')
        validator.trigger_notification.assert_called_once_with(task, 'regressed', ['eid.a'])
        update_doc = validator.client.update.call_args[0][2]
        self.assertEqual(update_doc['j']['head_check_status'], 'regressed')
        self.assertEqual(update_doc['j']['regressed_errids'], ['eid.a'])
        self.assertEqual(update_doc['j']['keep_me'], 'yes')

    def test_finalize_head_check_fixed_updates_task_and_notifies(self):
        validator = self._make_validator()
        validator.bisect_instance._poll_job_stats.return_value = ({'unrelated': 1}, 'success')
        validator.client.update.return_value = True
        validator.trigger_notification = MagicMock()
        task = {'id': 102, 'j': {'introduced_errids': ['eid.a'], 'keep_me': 'yes'}}

        with patch('head_validator.time.time', return_value=223344):
            status = validator._finalize_head_check(task, 'job-2', 'head-commit', ['eid.a'])

        self.assertEqual(status, 'fixed')
        validator.trigger_notification.assert_called_once_with(task, 'fixed', [])
        update_doc = validator.client.update.call_args[0][2]
        self.assertEqual(update_doc['j']['head_check_status'], 'fixed')
        self.assertEqual(update_doc['j']['regressed_errids'], [])
        self.assertEqual(update_doc['j']['keep_me'], 'yes')

    def test_mark_head_check_failed_writes_timeout_alert(self):
        validator = self._make_validator()
        task = {'id': 88, 'error_id': 'eid.timeout', 'j': {'keep_me': 'yes'}}

        with patch('head_validator.time.time', return_value=445566):
            validator._mark_head_check_failed(task, 'timeout while waiting for head job')

        validator.client.update.assert_called_once()
        update_doc = validator.client.update.call_args[0][2]
        self.assertEqual(update_doc['j']['head_check_status'], 'failed')
        self.assertEqual(update_doc['j']['head_check_failure_reason'], 'timeout while waiting for head job')
        self.assertEqual(update_doc['j']['keep_me'], 'yes')
        validator.notification_writer.write_timeout_alert.assert_called_once_with(
            task_id=88,
            error_id='eid.timeout',
            timeout_type='head_check',
            reason='timeout while waiting for head job',
        )

    def test_run_head_check_cycle_aggregates_success_failure_and_exceptions(self):
        validator = self._make_validator()
        validator.scan_verified_tasks = MagicMock(return_value=[
            {'id': 1}, {'id': 2}, {'id': 3}, {'id': 4}
        ])
        validator.check_head_regression = MagicMock(side_effect=[
            {'status': 'success', 'head_check_status': 'regressed'},
            {'status': 'success', 'head_check_status': 'fixed'},
            {'status': 'failed', 'error': 'boom'},
            RuntimeError('unexpected'),
        ])

        stats = validator.run_head_check_cycle()

        self.assertEqual(
            stats,
            {'scanned': 4, 'regressed': 1, 'fixed': 1, 'failed': 2}
        )

    def test_check_head_regression_skips_parent_verification_when_status_unchanged(self):
        validator = self._make_validator()
        validator.get_head_commit = MagicMock(return_value='head1234567890')
        validator.submit_head_test = MagicMock(return_value=('job-1', '/result-1'))
        validator.get_parent_commit = MagicMock()
        validator.update_head_check_status = MagicMock()
        validator.bisect_instance._poll_job_stats.return_value = ({'dummy': 1}, 'success')
        validator.bisect_instance._check_error_id.return_value = ('bad', None, None)

        task = {
            'id': 555,
            'bad_job_id': '42',
            'error_id': 'eid.a',
            'git_url': 'https://example.com/repo.git',
            'j': {'head_check_status': 'regressed'},
        }

        result = validator.check_head_regression(task)

        self.assertEqual(result['status'], 'success')
        self.assertEqual(result['head_check_status'], 'regressed')
        self.assertTrue(result['verified'])
        self.assertFalse(result['status_changed'])
        validator.get_parent_commit.assert_not_called()
        validator.update_head_check_status.assert_called_once_with(
            555, 'regressed', 'head1234567890', 'job-1', ['eid.a'],
            verified=True, status_changed=False
        )
        validator.client.sql_select.assert_not_called()
        validator._release_repo_to_pool.assert_called_once_with('/repo', '/job')

    def test_check_head_regression_verifies_parent_on_status_change(self):
        validator = self._make_validator()
        validator.get_head_commit = MagicMock(return_value='head1234567890')
        validator.submit_head_test = MagicMock(side_effect=[
            ('job-head', '/result-head'),
            ('job-parent', '/result-parent'),
        ])
        validator.get_parent_commit = MagicMock(return_value='parent12345678')
        validator.update_head_check_status = MagicMock()
        validator.trigger_notification = MagicMock()
        validator.notification_writer.write_bisect_success_report.return_value = '/tmp/report'
        validator.bisect_instance._poll_job_stats.side_effect = [
            ({'head': 1}, 'success'),
            ({'parent': 1}, 'success'),
        ]
        validator.bisect_instance._check_error_id.side_effect = [
            ('bad', None, None),
            ('good', None, None),
        ]
        validator.client.sql_select.side_effect = [
            [{'id': 556, 'j': {'introduced_errids': ['eid.a']}}],
            [{'id': 42, 'suite': 'boot'}],
        ]

        task = {
            'id': 556,
            'bad_job_id': '42',
            'error_id': 'eid.a',
            'git_url': 'https://example.com/repo.git',
            'j': {'head_check_status': 'fixed'},
        }

        result = validator.check_head_regression(task)

        self.assertEqual(result['status'], 'success')
        self.assertEqual(result['head_check_status'], 'regressed')
        self.assertTrue(result['verified'])
        self.assertTrue(result['status_changed'])
        validator.get_parent_commit.assert_called_once_with('/repo', 'head1234567890')
        validator.trigger_notification.assert_called_once_with(task, 'regressed', ['eid.a'])
        validator.update_head_check_status.assert_called_once_with(
            556, 'regressed', 'head1234567890', 'job-head', ['eid.a'],
            verified=True, status_changed=True
        )
        validator.notification_writer.write_bisect_success_report.assert_called_once()
        validator._release_repo_to_pool.assert_called_once_with('/repo', '/job')


if __name__ == '__main__':
    unittest.main()
