#!/usr/bin/env python3
"""Tests for BatchInserter result-root allocation and rollback paths."""

import os
import sys
import types
import unittest
from unittest.mock import MagicMock, patch


# Stub external modules before importing BatchInserter, so we can drive
# _generate_task_id / generate_task_path deterministically.
for name in ['log_config', 'bisect_utils']:
    if name not in sys.modules:
        sys.modules[name] = types.ModuleType(name)
sys.modules['log_config'].logger = MagicMock()
sys.modules['bisect_utils']._generate_task_id = MagicMock()
sys.modules['bisect_utils'].generate_task_path = MagicMock()

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'lib'))
sys.modules.pop('batch_inserter', None)

from batch_inserter import BatchInserter


class TestBatchInserterResultRoot(unittest.TestCase):

    def setUp(self):
        self.bu = sys.modules['bisect_utils']
        self.bu._generate_task_id.reset_mock(return_value=True, side_effect=True)
        self.bu.generate_task_path.reset_mock(return_value=True, side_effect=True)
        self.client = MagicMock()
        self.inserter = BatchInserter(self.client, batch_size=10)

    def _stub_id_and_path(self, task_id, path):
        self.bu._generate_task_id.return_value = task_id
        self.bu.generate_task_path.return_value = path

    def test_batch_insert_writes_result_root_into_doc(self):
        self._stub_id_and_path('tid-1', '/tmp/bi-1')
        self.client.batch_insert.return_value = True
        task = {
            'bad_job_id': 'job-A',
            'error_id': 'err-A',
            'git_url': 'https://example.com/foo.git',
        }

        success = self.inserter._batch_insert([task])

        self.assertEqual(success, 1)
        self.client.batch_insert.assert_called_once()
        index_arg, documents = self.client.batch_insert.call_args.args
        self.assertEqual(index_arg, 'bisect')
        self.assertIn('tid-1', documents)
        self.assertEqual(documents['tid-1']['bisect_result_root'], '/tmp/bi-1')

    def test_batch_insert_skips_task_when_path_allocation_fails(self):
        self.bu._generate_task_id.return_value = 'tid-bad'
        self.bu.generate_task_path.side_effect = OSError('disk full')
        self.client.batch_insert.return_value = True
        task = {'bad_job_id': 'job-A', 'error_id': 'err-A'}

        success = self.inserter._batch_insert([task])

        # Task is skipped (no documents); batch_insert sees empty dict and we
        # short-circuit to 0 without calling it.
        self.assertEqual(success, 0)
        self.client.batch_insert.assert_not_called()

    def test_fallback_rmtree_when_replace_and_insert_both_return_false(self):
        self._stub_id_and_path('tid-2', '/tmp/bi-2')
        self.client.replace.return_value = False
        self.client.insert.return_value = False
        task = {'bad_job_id': 'job-A', 'error_id': 'err-A'}

        with patch('shutil.rmtree') as rmtree_mock:
            success, failed = self.inserter._fallback_single_insert([task])

        self.assertEqual((success, failed), (0, 1))
        rmtree_mock.assert_called_once_with('/tmp/bi-2', ignore_errors=True)

    def test_fallback_rmtree_when_client_raises(self):
        self._stub_id_and_path('tid-3', '/tmp/bi-3')
        self.client.replace.side_effect = RuntimeError('client down')
        task = {'bad_job_id': 'job-A', 'error_id': 'err-A'}

        with patch('shutil.rmtree') as rmtree_mock:
            success, failed = self.inserter._fallback_single_insert([task])

        self.assertEqual((success, failed), (0, 1))
        rmtree_mock.assert_called_once_with('/tmp/bi-3', ignore_errors=True)

    def test_fallback_keeps_dir_on_replace_success(self):
        self._stub_id_and_path('tid-4', '/tmp/bi-4')
        self.client.replace.return_value = True
        task = {'bad_job_id': 'job-A', 'error_id': 'err-A'}

        with patch('shutil.rmtree') as rmtree_mock:
            success, failed = self.inserter._fallback_single_insert([task])

        self.assertEqual((success, failed), (1, 0))
        rmtree_mock.assert_not_called()


if __name__ == '__main__':
    unittest.main()
