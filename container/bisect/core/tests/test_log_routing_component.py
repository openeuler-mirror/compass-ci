#!/usr/bin/env python3
"""Tests for component-aware log routing helpers."""

import os
import sys
import unittest
import importlib.util

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
LIB_PATH = os.path.join(REPO_ROOT, 'container', 'bisect', 'lib')
LOG_CONFIG_PATH = os.path.join(LIB_PATH, 'log_config.py')

spec = importlib.util.spec_from_file_location('bisect_log_config_test', LOG_CONFIG_PATH)
log_config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(log_config)

get_log_component = log_config.get_log_component
resolve_log_component = log_config.resolve_log_component
set_log_component = log_config.set_log_component


class TestLogRoutingComponent(unittest.TestCase):

    def tearDown(self):
        set_log_component(None)

    def test_thread_component_takes_effect(self):
        set_log_component('producer')
        self.assertEqual(get_log_component(), 'producer')
        self.assertEqual(resolve_log_component('/any/path.py', ''), 'producer')

    def test_explicit_record_component_has_highest_priority(self):
        set_log_component('consumer')
        self.assertEqual(
            resolve_log_component('/services/commit_time_service/server.py', 'producer'),
            'producer'
        )

    def test_path_fallback_when_no_component_set(self):
        self.assertEqual(
            resolve_log_component('/c/compass-ci/container/bisect/services/commit_time_service/server.py', ''),
            'commit_time_service'
        )
        self.assertEqual(
            resolve_log_component('/c/compass-ci/container/bisect/core/bisect_producer.py', ''),
            'producer'
        )
        self.assertEqual(
            resolve_log_component('/c/lkp-tests/sbin/bisect/lkp_bisect/db/manticore.py', ''),
            'consumer'
        )


if __name__ == '__main__':
    unittest.main()
