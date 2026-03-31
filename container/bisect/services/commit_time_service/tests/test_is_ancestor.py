#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Unit tests for is_ancestor feature across client and server layers
"""

import os
import sys
import unittest
from unittest.mock import Mock, patch, MagicMock

# Set environment variables
os.environ['CCI_SRC'] = '/srv/cci'
os.environ['WORK_DIR'] = '/tmp'
os.environ['LKP_SRC'] = '/srv/lkp'

# Add project paths
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from client import CommitTimeClient


class TestCommitTimeClientIsAncestor(unittest.TestCase):
    """Tests for CommitTimeClient.is_ancestor"""

    def setUp(self):
        self.client = CommitTimeClient('http://localhost:8765', timeout=5)

    @patch('client.requests.get')
    def test_is_ancestor_true(self, mock_get):
        """Service returns is_ancestor=True"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'status': 'success',
            'data': {'is_ancestor': True, 'ancestor': 'aaa', 'descendant': 'bbb'}
        }
        mock_get.return_value = mock_response

        result = self.client.is_ancestor('http://repo', 'aaa', 'bbb')
        self.assertTrue(result)

        # Verify correct endpoint and params
        mock_get.assert_called_once()
        call_kwargs = mock_get.call_args
        self.assertIn('/api/v1/commit/is-ancestor', call_kwargs[0][0])
        self.assertEqual(call_kwargs[1]['params']['ancestor'], 'aaa')
        self.assertEqual(call_kwargs[1]['params']['descendant'], 'bbb')

    @patch('client.requests.get')
    def test_is_ancestor_false(self, mock_get):
        """Service returns is_ancestor=False"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'status': 'success',
            'data': {'is_ancestor': False, 'ancestor': 'aaa', 'descendant': 'bbb'}
        }
        mock_get.return_value = mock_response

        result = self.client.is_ancestor('http://repo', 'aaa', 'bbb')
        self.assertFalse(result)

    @patch('client.requests.get')
    def test_is_ancestor_service_error(self, mock_get):
        """Service returns error status"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'status': 'error',
            'error': 'Ancestor check failed'
        }
        mock_get.return_value = mock_response

        result = self.client.is_ancestor('http://repo', 'aaa', 'bbb')
        self.assertIsNone(result)

    @patch('client.requests.get')
    def test_is_ancestor_connection_error(self, mock_get):
        """Connection failure returns None (graceful degradation)"""
        mock_get.side_effect = Exception("Connection refused")

        result = self.client.is_ancestor('http://repo', 'aaa', 'bbb')
        self.assertIsNone(result)

    @patch('client.requests.get')
    def test_is_ancestor_http_500(self, mock_get):
        """HTTP 500 returns None"""
        mock_response = Mock()
        mock_response.status_code = 500
        mock_get.return_value = mock_response

        result = self.client.is_ancestor('http://repo', 'aaa', 'bbb')
        self.assertIsNone(result)


class TestCommitTimeClientBatchIsAncestor(unittest.TestCase):
    """Tests for CommitTimeClient.batch_is_ancestor"""

    def setUp(self):
        self.client = CommitTimeClient('http://localhost:8765', timeout=5)

    @patch('client.requests.post')
    def test_batch_all_ancestors(self, mock_post):
        """All pairs are ancestors"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'status': 'success',
            'data': {
                'total': 3,
                'results': [
                    {'ancestor': 'a1', 'descendant': 'b1', 'is_ancestor': True},
                    {'ancestor': 'a2', 'descendant': 'b2', 'is_ancestor': True},
                    {'ancestor': 'a3', 'descendant': 'b3', 'is_ancestor': True},
                ]
            }
        }
        mock_post.return_value = mock_response

        pairs = [('a1', 'b1'), ('a2', 'b2'), ('a3', 'b3')]
        results = self.client.batch_is_ancestor('http://repo', pairs)
        self.assertEqual(results, [True, True, True])

    @patch('client.requests.post')
    def test_batch_mixed_results(self, mock_post):
        """Mix of True, False, None results"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'status': 'success',
            'data': {
                'total': 3,
                'results': [
                    {'ancestor': 'a1', 'descendant': 'b1', 'is_ancestor': True},
                    {'ancestor': 'a2', 'descendant': 'b2', 'is_ancestor': False},
                    {'ancestor': 'a3', 'descendant': 'b3', 'is_ancestor': None},
                ]
            }
        }
        mock_post.return_value = mock_response

        pairs = [('a1', 'b1'), ('a2', 'b2'), ('a3', 'b3')]
        results = self.client.batch_is_ancestor('http://repo', pairs)
        self.assertEqual(results, [True, False, None])

    @patch('client.requests.post')
    def test_batch_service_error_returns_nones(self, mock_post):
        """Service error returns all None (graceful degradation)"""
        mock_response = Mock()
        mock_response.status_code = 500
        mock_post.return_value = mock_response

        pairs = [('a1', 'b1'), ('a2', 'b2')]
        results = self.client.batch_is_ancestor('http://repo', pairs)
        self.assertEqual(results, [None, None])

    @patch('client.requests.post')
    def test_batch_connection_error_returns_nones(self, mock_post):
        """Connection error returns all None"""
        mock_post.side_effect = Exception("Connection refused")

        pairs = [('a1', 'b1')]
        results = self.client.batch_is_ancestor('http://repo', pairs)
        self.assertEqual(results, [None])

    def test_batch_empty_pairs(self):
        """Empty pairs returns empty list"""
        results = self.client.batch_is_ancestor('http://repo', [])
        self.assertEqual(results, [])


class TestCommitTimeClientBatchCheckAncestry(unittest.TestCase):
    """Tests for CommitTimeClient.batch_check_ancestry (uses batch endpoint)"""

    def setUp(self):
        self.client = CommitTimeClient('http://localhost:8765', timeout=5)

    @patch('client.requests.post')
    def test_batch_all_valid(self, mock_post):
        """All pairs are valid ancestors → empty invalid set"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'status': 'success',
            'data': {
                'total': 3,
                'results': [
                    {'ancestor': 'a1', 'descendant': 'b1', 'is_ancestor': True},
                    {'ancestor': 'a2', 'descendant': 'b2', 'is_ancestor': True},
                    {'ancestor': 'a3', 'descendant': 'b3', 'is_ancestor': True},
                ]
            }
        }
        mock_post.return_value = mock_response

        pairs = [('a1', 'b1'), ('a2', 'b2'), ('a3', 'b3')]
        invalid = self.client.batch_check_ancestry('http://repo', pairs)
        self.assertEqual(invalid, set())

    @patch('client.requests.post')
    def test_batch_some_invalid(self, mock_post):
        """False results → invalid indices; None results → skipped"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'status': 'success',
            'data': {
                'total': 3,
                'results': [
                    {'ancestor': 'a1', 'descendant': 'b1', 'is_ancestor': True},
                    {'ancestor': 'a2', 'descendant': 'b2', 'is_ancestor': False},
                    {'ancestor': 'a3', 'descendant': 'b3', 'is_ancestor': None},
                ]
            }
        }
        mock_post.return_value = mock_response

        pairs = [('a1', 'b1'), ('a2', 'b2'), ('a3', 'b3')]
        invalid = self.client.batch_check_ancestry('http://repo', pairs)
        # Only index 1 (False) is invalid; index 2 (None) is skipped
        self.assertEqual(invalid, {1})

    def test_batch_empty_pairs(self):
        """Empty pairs list returns empty set"""
        invalid = self.client.batch_check_ancestry('http://repo', [])
        self.assertEqual(invalid, set())


class TestServiceIsAncestorEndpoint(unittest.TestCase):
    """Tests for CommitTimeService.check_ancestor"""

    def setUp(self):
        from server import CommitTimeService
        self.service = CommitTimeService.__new__(CommitTimeService)
        self.service.query = Mock()
        self.service.request_count = 0

    def test_check_ancestor_success_true(self):
        self.service.query.is_ancestor.return_value = True
        result = self.service.check_ancestor('http://repo', 'aaa', 'bbb')
        self.assertEqual(result['status'], 'success')
        self.assertTrue(result['data']['is_ancestor'])
        self.assertEqual(result['data']['ancestor'], 'aaa')
        self.assertEqual(result['data']['descendant'], 'bbb')
        self.assertEqual(self.service.request_count, 1)

    def test_check_ancestor_success_false(self):
        self.service.query.is_ancestor.return_value = False
        result = self.service.check_ancestor('http://repo', 'aaa', 'bbb')
        self.assertEqual(result['status'], 'success')
        self.assertFalse(result['data']['is_ancestor'])

    def test_check_ancestor_exception(self):
        self.service.query.is_ancestor.side_effect = Exception("git error")
        result = self.service.check_ancestor('http://repo', 'aaa', 'bbb')
        self.assertEqual(result['status'], 'error')
        self.assertIn('git error', result['error'])

    def test_check_ancestor_unknown_returns_structured_error(self):
        self.service.query.is_ancestor.return_value = None
        result = self.service.check_ancestor('http://repo', 'aaa', 'bbb')
        self.assertEqual(result['status'], 'error')
        self.assertEqual(result.get('error_code'), 'unable_to_determine_ancestor')
        self.assertTrue(result.get('retryable'))


class TestServiceBatchIsAncestor(unittest.TestCase):
    """Tests for CommitTimeService.batch_check_ancestor"""

    def setUp(self):
        from server import CommitTimeService
        self.service = CommitTimeService.__new__(CommitTimeService)
        self.service.query = Mock()
        self.service.request_count = 0

    def test_batch_all_true(self):
        self.service.query.is_ancestor.return_value = True
        pairs = [
            {'ancestor': 'a1', 'descendant': 'b1'},
            {'ancestor': 'a2', 'descendant': 'b2'},
        ]
        result = self.service.batch_check_ancestor('http://repo', pairs)
        self.assertEqual(result['status'], 'success')
        self.assertEqual(len(result['data']['results']), 2)
        self.assertTrue(all(r['is_ancestor'] for r in result['data']['results']))

    def test_batch_mixed_results(self):
        # Use deterministic mapping since ThreadPoolExecutor order is non-deterministic
        def mock_is_ancestor(git_url, ancestor, descendant):
            return {'a1': True, 'a2': False, 'a3': None}[ancestor]

        self.service.query.is_ancestor.side_effect = mock_is_ancestor
        pairs = [
            {'ancestor': 'a1', 'descendant': 'b1'},
            {'ancestor': 'a2', 'descendant': 'b2'},
            {'ancestor': 'a3', 'descendant': 'b3'},
        ]
        result = self.service.batch_check_ancestor('http://repo', pairs)
        self.assertEqual(result['status'], 'success')
        results = result['data']['results']
        self.assertTrue(results[0]['is_ancestor'])
        self.assertFalse(results[1]['is_ancestor'])
        self.assertIsNone(results[2]['is_ancestor'])

    def test_batch_empty_pairs(self):
        result = self.service.batch_check_ancestor('http://repo', [])
        self.assertEqual(result['status'], 'success')
        self.assertEqual(result['data']['results'], [])


if __name__ == '__main__':
    unittest.main()
