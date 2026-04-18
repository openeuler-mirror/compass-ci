#!/usr/bin/env python3
"""Tests for verification-state recovery on TaskProcessor startup."""

import os
import sys
import types
import threading
import unittest
from unittest.mock import MagicMock


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
        return 1


sys.modules['config'].Config = _DummyConfig()
sys.modules['lkp_bisect.db.manticore'].ManticoreClient = MagicMock


class _DummyGitBisect:
    def __init__(self, *args, **kwargs):
        pass


sys.modules['lkp_bisect.core.git_bisect'].GitBisect = _DummyGitBisect
sys.modules['success_task_validator'].SuccessTaskValidator = MagicMock
sys.modules['head_validator'].HeadValidator = MagicMock
sys.modules['bisect_producer'].MetricsBisectProducer = MagicMock
sys.modules['bisect_producer'].KernelCIBisectProducer = MagicMock
sys.modules['bisect_producer'].ErrorBisectProducer = MagicMock
sys.modules['bisect_producer'].PerformanceBisectProducer = MagicMock
sys.modules['bisect_consumer'].BisectConsumer = MagicMock
sys.modules['polling_worker'].PollingWorker = object

os.environ.setdefault('CCI_SRC', '/tmp')
os.environ.setdefault('LKP_SRC', '/tmp')

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO_ROOT, 'container', 'bisect', 'core'))
sys.modules.pop('task_processor', None)

from task_processor import TaskProcessor


class TestTaskProcessorVerificationRecovery(unittest.TestCase):

    def _make_processor(self):
        p = TaskProcessor.__new__(TaskProcessor)
        p.client = MagicMock()
        p._success_signature_cache = {}
        p._success_cache_lock = threading.Lock()
        p._success_cache_last_refresh = 0
        p._success_cache_ttl = 3600
        return p

    def test_reconcile_keeps_submitted_jobs_and_requeues_incomplete_tasks(self):
        processor = self._make_processor()
        processor.client.sql_select.return_value = [
            {
                'id': 11,
                'j': {
                    'verification_status': 'verified',
                }
            },
            {
                'id': 12,
                'j': {
                    'verification_status': 'submitted',
                    'verification_jobs': {
                        'status': 'submitted',
                        'parent_job_id': 'p12',
                        'candidate_job_id': 'c12',
                    }
                }
            },
            {
                'id': 13,
                'j': {
                    'verification_status': 'timeout',
                    'verification_jobs': {
                        'status': 'retry_pending',
                    }
                }
            },
        ]

        recovered = processor._reconcile_verifying_tasks_on_startup(current_time=1234)

        self.assertEqual(recovered, 2)
        update_calls = processor.client.update.call_args_list
        updated_ids = [call.args[1] for call in update_calls]
        self.assertIn(11, updated_ids)
        self.assertIn(13, updated_ids)
        self.assertNotIn(12, updated_ids)

        update_by_id = {call.args[1]: call.args[2] for call in update_calls}
        self.assertEqual(update_by_id[11]['bisect_status'], 'success')
        self.assertEqual(update_by_id[13]['bisect_status'], 'pending_verification')
        self.assertEqual(update_by_id[13]['j']['verification_status'], 'pending')
        self.assertEqual(update_by_id[13]['j']['startup_recovery_from'], 'verifying')


if __name__ == '__main__':
    unittest.main()
