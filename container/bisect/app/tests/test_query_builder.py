#!/usr/bin/env python3
"""Tests for bisect API query condition building."""

import os
import sys
import unittest

from flask import Flask


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO_ROOT, 'container', 'bisect', 'lib'))

import query_builder


class TestQueryBuilder(unittest.TestCase):

    def setUp(self):
        self.app = Flask(__name__)

    def test_short_commit_uses_regex_prefix_match(self):
        with self.app.test_request_context('/?first_bad_commit=b6596f83'):
            where_clause, filters = query_builder.build_task_query_conditions()

        self.assertIn("REGEX(first_bad_commit, '^b6596f83')", where_clause)
        self.assertEqual(filters['first_bad_commit'], 'b6596f83')

    def test_full_commit_uses_exact_match(self):
        commit = 'b6596f8311d9a69b88e935b0bc2fb0a380a11b54'
        with self.app.test_request_context(f'/?first_bad_commit={commit}'):
            where_clause, filters = query_builder.build_task_query_conditions()

        self.assertIn(f"first_bad_commit = '{commit}'", where_clause)
        self.assertEqual(filters['first_bad_commit'], commit)

    def test_git_url_uses_regex_filter(self):
        with self.app.test_request_context('/?git_url=openeuler-kernel'):
            where_clause, filters = query_builder.build_task_query_conditions()

        self.assertIn("REGEX(git_url, 'openeuler\\\\-kernel')", where_clause)
        self.assertEqual(filters['git_url'], 'openeuler-kernel')

    def test_error_id_uses_exact_match(self):
        error_id = "makepkg.eid.fs/#p/vfs_file.c:warning"
        with self.app.test_request_context('/', query_string={'error_id': error_id}):
            where_clause, filters = query_builder.build_task_query_conditions()

        self.assertIn("error_id = 'makepkg.eid.fs/#p/vfs_file.c:warning'", where_clause)
        self.assertEqual(filters['error_id'], error_id)

    def test_task_id_is_validated_and_mapped(self):
        with self.app.test_request_context('/?task_id=123'):
            where_clause, filters = query_builder.build_task_query_conditions()

        self.assertIn('id = 123', where_clause)
        self.assertEqual(filters['task_id'], 123)


if __name__ == '__main__':
    unittest.main()
