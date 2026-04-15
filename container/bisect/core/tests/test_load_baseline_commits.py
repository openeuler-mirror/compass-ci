#!/usr/bin/env python3
"""Tests for PerformanceBisectProducer._load_baseline_commits()"""

import sys
import types
import unittest
from unittest.mock import patch, mock_open, MagicMock
import yaml

# Stub out heavy external dependencies before importing bisect_producer
for mod_name in [
    'lkp_bisect', 'lkp_bisect.db', 'lkp_bisect.db.manticore',
    'log_config', 'bisect_utils', 'producer_reporter', 'lru_cache',
    'batch_inserter', 'config',
]:
    if mod_name not in sys.modules:
        sys.modules[mod_name] = types.ModuleType(mod_name)

# Provide required attributes on stubs
sys.modules['lkp_bisect.db.manticore'].ManticoreClient = MagicMock
sys.modules['log_config'].logger = MagicMock()
for attr in [
    'smart_split_error_ids', 'extract_git_url_from_full_text_kv',
    'extract_commit_from_full_text_kv', 'get_repo_info_from_job_data',
    'write_analysis_files', 'extract_repo_name_from_url',
    'categorize_bisect_task', 'format_error_ids',
]:
    setattr(sys.modules['bisect_utils'], attr, MagicMock())
sys.modules['producer_reporter'].ProducerReporter = MagicMock
sys.modules['lru_cache'].LRUCache = MagicMock
sys.modules['batch_inserter'].BatchInserter = MagicMock
sys.modules['config'].Config = types.SimpleNamespace(CI_CONFIG_PATH='/tmp/ci_config.yaml')

# Also stub CommitTimeClient
sys.modules['client'] = types.ModuleType('client')
sys.modules['client'].CommitTimeClient = MagicMock

import os
os.environ.setdefault('CCI_SRC', '/tmp')

sys.modules.pop('bisect_producer', None)

from bisect_producer import PerformanceBisectProducer


SAMPLE_CI_CONFIG = yaml.dump({
    'kernel_test_matrix': [
        {
            'repo': 'openeuler-kernel',
            'branch': 'OLK-5.10',
            'baseline_tag': {'type': 'fixed', 'value': '5.10.0-216.0.0'},
            'current_tag': {'type': 'dynamic', 'pattern': '5.10.0-2*.0.0'},
            'test_types': 'all',
        },
        {
            'repo': 'openeuler-kernel',
            'branch': 'OLK-6.6',
            'baseline_tag': {'type': 'fixed', 'value': '6.6.0-98.0.0'},
            'current_tag': {'type': 'dynamic', 'pattern': '6.6.0-*.0.0'},
            'test_types': 'all',
        },
        {
            'repo': 'linux-next',
            'branch': 'master',
            'baseline_tag': {'type': 'fixed', 'value': 'v6.17'},
            'current_tag': {'type': 'dynamic', 'pattern': 'next-*'},
            'test_types': 'all',
        },
        {
            'repo': 'linux',
            'branch': 'master',
            'baseline_tag': {'type': 'fixed', 'value': 'v6.17'},
            'current_tag': {'type': 'dynamic', 'pattern': 'v6.18-rc*'},
            'test_types': 'all',
        },
    ]
})

DEFAULT_BASELINES = {
    '5.10.0-216.0.0': True,
    '6.6.0-98.0.0': True,
    'v6.17': True,
}


def _make_producer():
    """Create a PerformanceBisectProducer with mocked dependencies."""
    instance = PerformanceBisectProducer.__new__(PerformanceBisectProducer)
    return instance


class TestLoadBaselineCommits(unittest.TestCase):

    @patch('builtins.open', mock_open(read_data=SAMPLE_CI_CONFIG))
    def test_loads_fixed_baselines_from_yaml(self):
        producer = _make_producer()
        result = producer._load_baseline_commits()
        self.assertEqual(result, DEFAULT_BASELINES)

    @patch('builtins.open', side_effect=FileNotFoundError)
    def test_falls_back_on_file_not_found(self, _mock):
        producer = _make_producer()
        result = producer._load_baseline_commits()
        self.assertEqual(result, DEFAULT_BASELINES)

    @patch('builtins.open', mock_open(read_data='not: valid: yaml: ['))
    def test_falls_back_on_parse_error(self):
        producer = _make_producer()
        result = producer._load_baseline_commits()
        self.assertEqual(result, DEFAULT_BASELINES)

    @patch('builtins.open', mock_open(read_data=yaml.dump({
        'kernel_test_matrix': [
            {'repo': 'linux', 'branch': 'master'},
            {'repo': 'linux-next', 'branch': 'master', 'baseline_tag': {'type': 'dynamic', 'pattern': 'next-*'}},
        ]
    })))
    def test_skips_entries_without_fixed_baseline_tag(self):
        producer = _make_producer()
        result = producer._load_baseline_commits()
        # No fixed baselines found -> falls back to defaults
        self.assertEqual(result, DEFAULT_BASELINES)

    @patch('builtins.open', mock_open(read_data=yaml.dump({'settings': {}})))
    def test_falls_back_when_no_kernel_test_matrix(self):
        producer = _make_producer()
        result = producer._load_baseline_commits()
        self.assertEqual(result, DEFAULT_BASELINES)

    @patch('builtins.open', mock_open(read_data=yaml.dump({
        'kernel_test_matrix': [
            {'repo': 'openeuler-kernel', 'branch': 'OLK-5.10',
             'baseline_tag': {'type': 'fixed', 'value': '5.10.0-216.0.0'}},
            {'repo': 'openeuler-kernel', 'branch': 'OLK-6.6',
             'baseline_tag': {'type': 'fixed', 'value': '5.10.0-216.0.0'}},
        ]
    })))
    def test_deduplicates_baseline_tags(self):
        producer = _make_producer()
        result = producer._load_baseline_commits()
        self.assertEqual(result, {'5.10.0-216.0.0': True})


class TestQueryBaselineJobs(unittest.TestCase):
    """Tests for PerformanceBisectProducer._query_baseline_jobs()"""

    def _make_initialized_producer(self, baseline_commits=None):
        """Create a producer with enough attributes for _query_baseline_jobs."""
        producer = PerformanceBisectProducer.__new__(PerformanceBisectProducer)
        producer.baseline_commits = baseline_commits or {}
        producer.baseline_query_hours = 720
        producer.performance_suites = ['unixbench', 'stream']
        producer.client = MagicMock()
        return producer

    def test_returns_empty_when_no_baseline_commits(self):
        producer = self._make_initialized_producer(baseline_commits={})
        result = producer._query_baseline_jobs()
        self.assertEqual(result, [])
        producer.client.sql_select.assert_not_called()

    def test_uses_baseline_query_hours_for_time_threshold(self):
        producer = self._make_initialized_producer(
            baseline_commits={'v6.17': True, '5.10.0-216.0.0': True}
        )
        producer.client.sql_select.return_value = []

        with patch('time.time', return_value=1000000):
            producer._query_baseline_jobs()

        call_args = producer.client.sql_select.call_args[0][0]
        expected_threshold = 1000000 - 720 * 3600
        self.assertIn(str(expected_threshold), call_args)

    def test_filters_by_baseline_commits(self):
        producer = self._make_initialized_producer(
            baseline_commits={'v6.17': True, '5.10.0-216.0.0': True}
        )
        producer.client.sql_select.return_value = []

        producer._query_baseline_jobs()

        call_args = producer.client.sql_select.call_args[0][0]
        self.assertIn('v6.17', call_args)
        self.assertIn('5.10.0-216.0.0', call_args)
        self.assertIn("j.ss.linux.commit IN", call_args)

    def test_parses_returned_jobs(self):
        producer = self._make_initialized_producer(
            baseline_commits={'v6.17': True}
        )
        mock_item = {
            'id': 123,
            'suite': 'unixbench',
            'testbox': 'tbox1',
            'submit_time': 999999,
            'full_text_kv': 'git_url: https://git.kernel.org/linux.git\ncommit: abc123',
            'linux_commit': 'abc123',
            'j': {
                'ss': {'linux': {'commit': 'abc123'}},
                'stats': {'score': 100},
                'job_stage': 'finish',
                'job_health': 'success',
            },
        }
        producer.client.sql_select.return_value = [mock_item]

        # Mock the helpers that _parse_job_data calls
        with patch('bisect_producer.extract_git_url_from_full_text_kv', return_value='https://git.kernel.org/linux.git'), \
             patch('bisect_producer.extract_repo_name_from_url', return_value='linux'):
            result = producer._query_baseline_jobs()

        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['job_id'], '123')

    def test_handles_sql_exception(self):
        producer = self._make_initialized_producer(
            baseline_commits={'v6.17': True}
        )
        producer.client.sql_select.side_effect = Exception("DB error")

        result = producer._query_baseline_jobs()
        self.assertEqual(result, [])


if __name__ == '__main__':
    unittest.main()
