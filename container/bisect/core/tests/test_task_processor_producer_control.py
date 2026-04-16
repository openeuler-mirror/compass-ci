#!/usr/bin/env python3
"""Tests for runtime producer pause and resume control."""

import os
import sys
import types
import threading
import time
import unittest
from unittest.mock import MagicMock, patch


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
    BISECT_PRODUCER_ENABLED = True
    BISECT_METRICS_PRODUCER_ENABLED = True
    BISECT_ERROR_PRODUCER_ENABLED = True
    BISECT_KERNEL_CI_PRODUCER_ENABLED = True
    PERFORMANCE_PRODUCER_ENABLED = True
    BISECT_PRODUCER_SCHEDULED_ENABLED = False
    BISECT_PRODUCER_CYCLE_HOURS = 1

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

import task_processor
from task_processor import TaskProcessor


class TestTaskProcessorProducerControl(unittest.TestCase):

    def setUp(self):
        task_processor.Config.BISECT_PRODUCER_ENABLED = True
        task_processor.Config.BISECT_METRICS_PRODUCER_ENABLED = True
        task_processor.Config.BISECT_ERROR_PRODUCER_ENABLED = True
        task_processor.Config.BISECT_KERNEL_CI_PRODUCER_ENABLED = True
        task_processor.Config.PERFORMANCE_PRODUCER_ENABLED = True
        task_processor.Config.BISECT_PRODUCER_SCHEDULED_ENABLED = False
        task_processor.Config.BISECT_PRODUCER_CYCLE_HOURS = 1

    def _make_processor(self):
        processor = TaskProcessor.__new__(TaskProcessor)
        processor.client = MagicMock()
        processor._config = {}
        processor.add_bisect_task = MagicMock()
        processor.stop_event = threading.Event()
        processor.producer_control_event = threading.Event()
        processor.producer_lock = threading.Lock()
        processor.producer_interval = 3600
        processor.consumer_wake_event = MagicMock()
        processor._metrics_producer = None
        processor._kernel_ci_producer = None
        return processor

    def test_get_producer_gate_state_tracks_global_and_component_switches(self):
        processor = self._make_processor()
        task_processor.Config.BISECT_KERNEL_CI_PRODUCER_ENABLED = False
        task_processor.Config.PERFORMANCE_PRODUCER_ENABLED = False

        gate_state = processor.get_producer_gate_state()

        self.assertTrue(gate_state['configured_enabled'])
        self.assertEqual(gate_state['configured_producers'], ['metrics', 'error'])
        self.assertEqual(gate_state['effective_producers'], ['metrics', 'error'])
        self.assertFalse(gate_state['producers']['kernel_ci']['configured_enabled'])
        self.assertFalse(gate_state['producers']['performance']['configured_enabled'])

    def test_get_producer_gate_state_pauses_when_all_subproducers_disabled(self):
        processor = self._make_processor()
        task_processor.Config.BISECT_METRICS_PRODUCER_ENABLED = False
        task_processor.Config.BISECT_ERROR_PRODUCER_ENABLED = False
        task_processor.Config.BISECT_KERNEL_CI_PRODUCER_ENABLED = False
        task_processor.Config.PERFORMANCE_PRODUCER_ENABLED = False

        gate_state = processor.get_producer_gate_state()

        self.assertTrue(gate_state['configured_enabled'])
        self.assertFalse(gate_state['accepting_new_cycles'])
        self.assertEqual(gate_state['pause_reason'], 'no_enabled_producers')
        self.assertEqual(gate_state['effective_producers'], [])

    def test_run_producer_once_runs_only_selected_targets(self):
        processor = self._make_processor()
        metrics_producer = MagicMock()
        kernel_ci_producer = MagicMock()
        processor._metrics_producer = metrics_producer
        processor._kernel_ci_producer = kernel_ci_producer

        with patch.object(task_processor, 'ErrorBisectProducer') as error_cls, \
             patch.object(task_processor, 'PerformanceBisectProducer') as perf_cls:
            error_instance = error_cls.return_value
            perf_instance = perf_cls.return_value
            error_instance.execute_producer_cycle.return_value = 2
            perf_instance.execute_producer_cycle.return_value = 3

            processor._run_producer_once(force=True, producer_targets=['kernel_ci', 'performance'])

        metrics_producer.execute_producer_cycle.assert_not_called()
        kernel_ci_producer.execute_producer_cycle.assert_called_once_with(force_run=True)
        error_cls.assert_not_called()
        perf_cls.assert_called_once_with(processor.client, processor._config)
        perf_instance.execute_producer_cycle.assert_called_once_with()
        processor.consumer_wake_event.set.assert_called_once_with()

    def test_disable_pauses_future_interval_cycles(self):
        processor = self._make_processor()
        first_cycle_finished = threading.Event()
        run_count = {'value': 0}

        def run_once(**_kwargs):
            run_count['value'] += 1
            first_cycle_finished.set()

        processor._run_producer_once = run_once

        thread = threading.Thread(target=processor.bisect_producer, daemon=True)
        thread.start()
        self.assertTrue(first_cycle_finished.wait(1))

        task_processor.Config.BISECT_PRODUCER_ENABLED = False
        processor.wake_producer_control_worker()
        time.sleep(0.2)

        self.assertEqual(run_count['value'], 1)
        gate_state = processor.get_producer_gate_state()
        self.assertFalse(gate_state['accepting_new_cycles'])
        self.assertEqual(gate_state['pause_reason'], 'disabled')

        processor.running = False
        thread.join(1)
        self.assertFalse(thread.is_alive())

    def test_enable_resumes_after_runtime_pause(self):
        processor = self._make_processor()
        first_cycle_finished = threading.Event()
        second_cycle_finished = threading.Event()
        run_count = {'value': 0}

        def run_once(**_kwargs):
            run_count['value'] += 1
            if run_count['value'] == 1:
                first_cycle_finished.set()
            elif run_count['value'] == 2:
                second_cycle_finished.set()

        processor._run_producer_once = run_once

        thread = threading.Thread(target=processor.bisect_producer, daemon=True)
        thread.start()
        self.assertTrue(first_cycle_finished.wait(1))

        task_processor.Config.BISECT_PRODUCER_ENABLED = False
        processor.wake_producer_control_worker()
        time.sleep(0.2)
        self.assertEqual(run_count['value'], 1)

        task_processor.Config.BISECT_PRODUCER_ENABLED = True
        processor.wake_producer_control_worker()
        self.assertTrue(second_cycle_finished.wait(1))
        self.assertEqual(run_count['value'], 2)

        processor.running = False
        thread.join(1)
        self.assertFalse(thread.is_alive())


if __name__ == '__main__':
    unittest.main()
