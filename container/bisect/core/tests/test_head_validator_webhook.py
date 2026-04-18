#!/usr/bin/env python3
"""Tests for webhook delivery in HeadValidator notifications."""

import os
import sys
import types
import unittest
from unittest.mock import MagicMock, patch


# Stub external dependencies before importing target module.
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

from head_validator import HeadValidator


class TestHeadValidatorWebhook(unittest.TestCase):

    def _make_validator(self):
        v = HeadValidator.__new__(HeadValidator)
        v.notification_webhook = 'http://127.0.0.1:18080/webhook'
        v.notification_email = ''
        v.notification_writer = MagicMock()
        v._feishu = None
        return v

    @patch('head_validator.urllib.request.urlopen')
    def test_send_webhook_notification_success(self, mock_urlopen):
        validator = self._make_validator()
        response = MagicMock()
        response.status = 200
        response.getcode.return_value = 200
        response.__enter__.return_value = response
        response.__exit__.return_value = None
        mock_urlopen.return_value = response

        ok = validator._send_webhook_notification({
            'event': 'head_regression',
            'task_id': 123,
        })

        self.assertTrue(ok)
        mock_urlopen.assert_called_once()

    @patch('head_validator.urllib.request.urlopen')
    def test_send_webhook_notification_http_error(self, mock_urlopen):
        validator = self._make_validator()
        import urllib.error
        mock_urlopen.side_effect = urllib.error.HTTPError(
            url=validator.notification_webhook,
            code=500,
            msg='boom',
            hdrs=None,
            fp=None
        )

        ok = validator._send_webhook_notification({
            'event': 'head_regression',
            'task_id': 123,
        })
        self.assertFalse(ok)

    def test_trigger_notification_sends_webhook_for_regressed(self):
        validator = self._make_validator()
        validator._send_webhook_notification = MagicMock(return_value=True)
        validator._send_feishu_notification = MagicMock(return_value=False)

        task = {
            'id': 123,
            'error_id': 'eid',
            'first_bad_commit': 'abc123',
            'git_url': 'https://example.com/repo.git',
            'j': {'introduced_errids': ['eid.a', 'eid.b']},
        }
        validator.trigger_notification(task, 'regressed', ['eid.a'])

        validator.notification_writer.write_head_regression_alert.assert_called_once()
        validator._send_webhook_notification.assert_called_once()
        validator._send_feishu_notification.assert_called_once_with(task, 'regressed', ['eid.a'])
        payload = validator._send_webhook_notification.call_args[0][0]
        self.assertEqual(payload['event'], 'head_regression')
        self.assertEqual(payload['task_id'], 123)
        self.assertEqual(payload['regressed_errids'], ['eid.a'])

    def test_trigger_notification_sends_webhook_for_fixed(self):
        validator = self._make_validator()
        validator._send_webhook_notification = MagicMock(return_value=True)
        validator._send_feishu_notification = MagicMock(return_value=False)

        task = {
            'id': 456,
            'error_id': 'eid',
            'first_bad_commit': 'def456',
            'git_url': 'https://example.com/repo.git',
            'j': {'introduced_errids': ['eid.x', 'eid.y']},
        }
        validator.trigger_notification(task, 'fixed', [])

        validator.notification_writer.write_head_fixed_report.assert_called_once()
        validator._send_webhook_notification.assert_called_once()
        validator._send_feishu_notification.assert_called_once_with(task, 'fixed', [])
        payload = validator._send_webhook_notification.call_args[0][0]
        self.assertEqual(payload['event'], 'head_fixed')
        self.assertEqual(payload['task_id'], 456)
        self.assertEqual(payload['introduced_errids'], ['eid.x', 'eid.y'])

    def test_send_feishu_notification_for_regressed(self):
        validator = self._make_validator()
        validator._feishu = MagicMock(enabled=True)
        validator._feishu.send.return_value = True

        task = {
            'id': 123,
            'first_bad_commit': 'abc123def456',
            'git_url': 'https://example.com/repo.git',
            'j': {'introduced_errids': ['eid.a', 'eid.b']},
        }

        ok = validator._send_feishu_notification(task, 'regressed', ['eid.a'])

        self.assertTrue(ok)
        validator._feishu.send.assert_called_once()
        title, content = validator._feishu.send.call_args[0]
        self.assertIn('Regression', title)
        self.assertIn('abc123def456'[:12], title)
        self.assertIn('Task ID: 123', content)
        self.assertIn('eid.a', content)

    def test_send_feishu_notification_for_fixed(self):
        validator = self._make_validator()
        validator._feishu = MagicMock(enabled=True)
        validator._feishu.send.return_value = True

        task = {
            'id': 456,
            'first_bad_commit': 'def456abc789',
            'git_url': 'https://example.com/repo.git',
            'j': {'introduced_errids': ['eid.x', 'eid.y']},
        }

        ok = validator._send_feishu_notification(task, 'fixed', [])

        self.assertTrue(ok)
        validator._feishu.send.assert_called_once()
        title, content = validator._feishu.send.call_args[0]
        self.assertIn('Fixed', title)
        self.assertIn('def456abc789'[:12], title)
        self.assertIn('Task ID: 456', content)
        self.assertIn('Fixed Errids: 2', content)

    def test_send_feishu_notification_skips_when_not_configured(self):
        validator = self._make_validator()

        ok = validator._send_feishu_notification({'id': 1, 'j': {}}, 'regressed', ['eid.z'])

        self.assertFalse(ok)


if __name__ == '__main__':
    unittest.main()
