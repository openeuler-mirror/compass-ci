#!/usr/bin/env python3
"""Tests for performance producer subtest and pp_params_md5 isolation."""

import os
import sys
import types
import unittest
from unittest.mock import MagicMock


for mod_name in [
    'lkp_bisect', 'lkp_bisect.db', 'lkp_bisect.db.manticore',
    'log_config', 'bisect_utils', 'producer_reporter', 'lru_cache',
    'batch_inserter', 'client', 'config',
]:
    if mod_name not in sys.modules:
        sys.modules[mod_name] = types.ModuleType(mod_name)

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
sys.modules['client'].CommitTimeClient = MagicMock
sys.modules['config'].Config = types.SimpleNamespace(CI_CONFIG_PATH='/tmp/ci_config.yaml')

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO_ROOT, 'container', 'bisect', 'core'))
os.environ.setdefault('CCI_SRC', '/tmp')

sys.modules.pop('bisect_producer', None)

from bisect_producer import PerformanceBisectProducer


class TestPerformanceProducerSubtests(unittest.TestCase):

    def _make_producer(self):
        producer = PerformanceBisectProducer.__new__(PerformanceBisectProducer)
        producer.client = MagicMock()
        return producer

    def test_group_performance_jobs_separates_subtests(self):
        producer = self._make_producer()
        jobs = [
            {
                'repo_name': 'linux',
                'suite': 'stress-ng',
                'testbox': 'box-a',
                'pp_params_md5': 'md5-cpu',
                'j': {'pp': {'stress-ng': {'test': 'cpu'}}},
            },
            {
                'repo_name': 'linux',
                'suite': 'stress-ng',
                'testbox': 'box-a',
                'pp_params_md5': 'md5-vm',
                'j': {'pp': {'stress-ng': {'test': 'vm'}}},
            },
        ]

        groups = producer._group_performance_jobs(jobs)

        self.assertEqual(len(groups), 2)
        self.assertIn(('linux', 'stress-ng', 'box-a', 'md5-cpu', 'cpu'), groups)
        self.assertIn(('linux', 'stress-ng', 'box-a', 'md5-vm', 'vm'), groups)

    def test_generate_pair_key_includes_variant_identity(self):
        producer = self._make_producer()
        pair_cpu = {
            'baseline_commit': 'base',
            'current_commit': 'curr',
            'suite': 'stress-ng',
            'pp_params_md5': 'md5-cpu',
            'subtest': 'cpu',
        }
        pair_vm = {
            'baseline_commit': 'base',
            'current_commit': 'curr',
            'suite': 'stress-ng',
            'pp_params_md5': 'md5-vm',
            'subtest': 'vm',
        }

        self.assertNotEqual(
            producer._generate_pair_key(pair_cpu),
            producer._generate_pair_key(pair_vm),
        )

    def test_query_all_samples_uses_top_level_pp_params_md5_filter(self):
        producer = self._make_producer()
        producer.client.sql_select.return_value = []

        producer._query_all_samples_from_db(
            'base', 'stress-ng', 'box-a', 'stress-ng.RATE.ops_per_sec', 'md5-cpu'
        )

        sql = producer.client.sql_select.call_args[0][0]
        self.assertIn("pp_params_md5 = 'md5-cpu'", sql)
        self.assertNotIn("j.pp_params_md5", sql)

    def test_task_exists_for_metric_matches_same_variant_only(self):
        producer = self._make_producer()
        producer.client.search.return_value = [
            {
                'id': '1',
                'j': {
                    'baseline_commit': 'base',
                    'current_commit': 'curr',
                    'pp_params_md5': 'md5-cpu',
                    'subtest': 'cpu',
                },
            }
        ]
        pair = {
            'baseline_commit': 'base',
            'current_commit': 'curr',
            'pp_params_md5': 'md5-vm',
            'subtest': 'vm',
        }

        self.assertFalse(producer._task_exists_for_metric(pair, 'stress-ng.RATE.ops_per_sec'))

        pair['pp_params_md5'] = 'md5-cpu'
        pair['subtest'] = 'cpu'
        self.assertTrue(producer._task_exists_for_metric(pair, 'stress-ng.RATE.ops_per_sec'))


if __name__ == '__main__':
    unittest.main()
