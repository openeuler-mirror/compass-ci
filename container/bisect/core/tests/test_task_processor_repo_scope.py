#!/usr/bin/env python3
"""Tests for repo-scoped successful-task cache and clustering in TaskProcessor."""

import os
import sys
import types
import threading
import unittest
from unittest.mock import MagicMock, patch


# Stub heavy dependencies before importing task_processor.
for mod_name in [
    'log_config',
    'errid_intelligence',
    'notification_writer',
    'bisect_utils',
    'repo_manager',
    'config',
    'lkp_bisect', 'lkp_bisect.db', 'lkp_bisect.db.manticore',
    'lkp_bisect.core', 'lkp_bisect.core.git_bisect',
    'success_task_validator',
    'head_validator',
    'bisect_producer',
    'bisect_consumer',
    'polling_worker',
]:
    if mod_name not in sys.modules:
        sys.modules[mod_name] = types.ModuleType(mod_name)

sys.modules['log_config'].logger = MagicMock()
sys.modules['log_config'].StructuredLogger = MagicMock
sys.modules['log_config'].set_log_component = MagicMock
sys.modules['errid_intelligence'].ErridIntelligence = MagicMock
sys.modules['notification_writer'].NotificationWriter = MagicMock
for attr in [
    '_create_task_document',
    '_generate_task_id',
    'smart_split_error_ids',
    'extract_git_url_from_full_text_kv',
    'get_repo_info_from_job_data',
    'write_analysis_files',
    'extract_repo_name_from_url',
    'categorize_bisect_task',
    'format_error_ids',
    'validate_task_data',
    'batch_check_existing_tasks',
    'get_bisect_statistics',
    'cleanup_task_workspace',
    'mark_similar_wait_tasks_for_verification',
    'mark_introduced_errid_tasks_for_verification',
]:
    setattr(sys.modules['bisect_utils'], attr, MagicMock())
sys.modules['repo_manager'].SharedRepoManager = MagicMock
class _DummyConfig:
    TASK_REUSE_MIN_CONFIDENCE = 'high'
    NOTIFICATION_DIR = '/tmp'
    BISECT_THREADS = 1
    BISECT_MAX_CONCURRENT_CLONES = 1
    PARALLEL_VERIFICATION_JOBS = 1
    VERIFICATION_BATCH_SIZE = 1
    HEAD_CHECK_BATCH_SIZE = 1

    def __getattr__(self, _name):
        # TaskProcessor reads many Config fields during module init; return harmless defaults.
        return 1

sys.modules['config'].Config = _DummyConfig()
sys.modules['lkp_bisect.db.manticore'].ManticoreClient = MagicMock
class _DummyGitBisect:
    def __init__(self, *args, **kwargs):
        pass

sys.modules['lkp_bisect.core.git_bisect'].GitBisect = _DummyGitBisect
sys.modules['success_task_validator'].SuccessTaskValidator = MagicMock
sys.modules['head_validator'].HeadValidator = MagicMock
sys.modules['bisect_producer'].ErrorBisectProducer = MagicMock
sys.modules['bisect_producer'].PerformanceBisectProducer = MagicMock
sys.modules['bisect_consumer'].BisectConsumer = MagicMock
sys.modules['polling_worker'].PollingWorker = object

os.environ.setdefault('CCI_SRC', '/tmp')
os.environ.setdefault('LKP_SRC', '/tmp')

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO_ROOT, 'container', 'bisect', 'core'))

from task_processor import TaskProcessor


class TestTaskProcessorRepoScope(unittest.TestCase):

    def _make_processor(self):
        p = TaskProcessor.__new__(TaskProcessor)
        p.client = MagicMock()
        p._success_signature_cache = {}
        p._success_cache_lock = threading.Lock()
        p._success_cache_last_refresh = 0
        p._success_cache_ttl = 3600
        return p

    def test_success_cache_is_repo_scoped(self):
        p = self._make_processor()
        p.client.sql_select.return_value = [
            {
                'id': 1,
                'error_id': 'err-a',
                'j': {'confidence': 'high'},
                'updated_at': 100,
                'git_url': 'git://repo/a.git',
                'category': 'build',
            },
            {
                'id': 2,
                'error_id': 'err-b',
                'j': {'confidence': 'high'},
                'updated_at': 101,
                'git_url': 'git://repo/b.git',
                'category': 'build',
            },
        ]

        with patch('task_processor.ErridIntelligence') as mock_intel:
            mock_intel.return_value.extract_coarse_signature.return_value = 'same-signature'
            p._refresh_success_signature_cache()

        self.assertEqual(len(p._success_signature_cache), 2)
        p._success_cache_last_refresh = 10**9  # avoid refresh path in lookup
        with patch('task_processor.time.time', return_value=10**9 + 1):
            self.assertEqual(
                p._find_successful_task_by_signature('same-signature', 'git://repo/a.git')['id'],
                1
            )
            self.assertEqual(
                p._find_successful_task_by_signature('same-signature', 'git://repo/b.git')['id'],
                2
            )

    def test_cluster_and_select_does_not_cross_repo_link(self):
        p = self._make_processor()
        p.client.update.return_value = True

        candidates = [
            {
                'id': 10,
                'category': 'build',
                'error_id': 'err-x',
                'git_url': 'git://repo/a.git',
                'j': {},
                'priority_level': 1,
                'submit_time': 100,
            },
            {
                'id': 20,
                'category': 'build',
                'error_id': 'err-y',
                'git_url': 'git://repo/b.git',
                'j': {},
                'priority_level': 1,
                'submit_time': 99,
            },
        ]

        def find_success(signature, git_url):
            if git_url == 'git://repo/a.git':
                return {'id': 111, 'j': {'confidence': 'high'}}
            return None

        p._find_successful_task_by_signature = MagicMock(side_effect=find_success)

        with patch('task_processor.ErridIntelligence') as mock_intel:
            mock_intel.return_value.extract_coarse_signature.return_value = 'same-signature'
            selected = p._cluster_and_select_tasks(candidates, max_selection=10)

        updated_ids = [call.args[1] for call in p.client.update.call_args_list]
        self.assertIn(10, updated_ids)      # same-repo task linked to successful task
        self.assertNotIn(20, updated_ids)   # cross-repo task must not be linked
        self.assertEqual([t['id'] for t in selected], [20])  # repo-b task remains for independent bisect


if __name__ == '__main__':
    unittest.main()
