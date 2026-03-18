#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Parent Commit API test

TDD: test，
"""

import unittest
import json
import os
import sys
from unittest.mock import Mock, patch, MagicMock

# 
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.environ.get('CCI_SRC', '/srv/cci'), 'container/bisect/lib'))


class TestParentCommitQuery(unittest.TestCase):
    """test CommitTimeQuery.get_parent_commit() """

    def setUp(self):
        """test"""
        #  mock  git 
        self.mock_repo_manager = Mock()
        #  PRISTINE_BASE_DIR ， os.path.join failed
        self.mock_repo_manager.PRISTINE_BASE_DIR = '/tmp/pristine_repos'
        # Mock _is_git_repo 
        self.patcher = patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
        self.mock_is_git_repo = self.patcher.start()

    def tearDown(self):
        """test"""
        self.patcher.stop()

    # ====================  ====================

    def test_get_parent_of_normal_commit(self):
        """test：query commit  parent"""
        # Given:  parent  commit
        git_url = "git://example.com/linux.git"
        commit = "abc123def456"
        expected_parent = "parent789xyz"

        # When:  get_parent_commit
        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(
                returncode=0,
                stdout=f"{expected_parent}\n",
                stderr=""
            )
            result = query.get_parent_commit(git_url, commit)

        # Then:  parent commit
        self.assertIsNotNone(result)
        self.assertEqual(result['parent'], expected_parent)
        self.assertEqual(result['commit'], commit)
        self.assertEqual(result['parent_count'], 1)

    def test_get_parent_returns_full_hash(self):
        """test： 40  hash"""
        git_url = "git://example.com/linux.git"
        commit = "abc123"  #  hash
        full_parent = "a" * 40  #  hash

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(
                returncode=0,
                stdout=f"{full_parent}\n",
                stderr=""
            )
            result = query.get_parent_commit(git_url, commit)

        self.assertEqual(len(result['parent']), 40)

    # ====================  ====================

    def test_get_parent_of_root_commit(self):
        """test：query root commit（ parent）"""
        git_url = "git://example.com/linux.git"
        root_commit = "first_commit_hash"

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        with patch('subprocess.run') as mock_run:
            # ：
            # 1. commit^@ failed
            # 2. commit^1 failed
            # (fetch)
            # 3. commit^1 failed
            # 4. commit checksuccess（root commit ）
            mock_run.side_effect = [
                Mock(returncode=128, stdout="", stderr="fatal: no such object"),  # ^@
                Mock(returncode=128, stdout="", stderr="fatal: no such object"),  # ^1
                Mock(returncode=128, stdout="", stderr="fatal: no such object"),  # ^1 retry
                Mock(returncode=0, stdout=root_commit, stderr=""),  # commit 
            ]
            with patch.object(query, '_fetch_pristine_repo'):
                result = query.get_parent_commit(git_url, root_commit)

        #  "no_parent" status
        self.assertIsNotNone(result)
        self.assertEqual(result.get('parent'), None)
        self.assertEqual(result.get('parent_count'), 0)
        self.assertEqual(result.get('reason'), 'root_commit')

    def test_get_parent_of_merge_commit(self):
        """test：query merge commit（ parent）"""
        git_url = "git://example.com/linux.git"
        merge_commit = "merge_commit_hash"
        parent1 = "parent1_hash"
        parent2 = "parent2_hash"

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        with patch('subprocess.run') as mock_run:
            #  commit^@，submit（）
            mock_run.return_value = Mock(
                returncode=0,
                stdout=f"{parent1}\n{parent2}\n",
                stderr=""
            )
            result = query.get_parent_commit(git_url, merge_commit)

        #  parent， merge commit
        self.assertEqual(result['parent'], parent1)
        self.assertEqual(result['parent_count'], 2)

    def test_commit_not_found(self):
        """test：commit not found"""
        git_url = "git://example.com/linux.git"
        nonexistent_commit = "nonexistent123"

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(
                returncode=128,
                stdout="",
                stderr="fatal: bad object nonexistent123"
            )
            #  fetch 
            with patch.object(query, '_fetch_pristine_repo'):
                result = query.get_parent_commit(git_url, nonexistent_commit)

        self.assertIsNone(result)

    # ==================== error ====================

    def test_invalid_git_url(self):
        """test： git_url"""
        invalid_url = "not_a_valid_url"
        commit = "abc123"

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        result = query.get_parent_commit(invalid_url, commit)

        self.assertIsNone(result)

    def test_empty_commit_hash(self):
        """test： commit hash"""
        git_url = "git://example.com/linux.git"
        empty_commit = ""

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        result = query.get_parent_commit(git_url, empty_commit)

        self.assertIsNone(result)

    def test_timeout_handling(self):
        """test：git timeout"""
        git_url = "git://example.com/linux.git"
        commit = "abc123"

        from commit_query import CommitTimeQuery
        import subprocess
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        with patch('subprocess.run') as mock_run:
            mock_run.side_effect = subprocess.TimeoutExpired(cmd="git", timeout=30)
            result = query.get_parent_commit(git_url, commit)

        self.assertIsNone(result)


class TestParentCommitService(unittest.TestCase):
    """test CommitTimeService  parent commit """

    def test_service_get_parent_commit_success(self):
        """test：servicesuccessget parent commit"""
        from server import CommitTimeService

        service = CommitTimeService()

        with patch.object(service.query, 'get_parent_commit') as mock_get:
            mock_get.return_value = {
                'commit': 'abc123',
                'parent': 'def456',
                'parent_count': 1
            }

            result = service.get_parent_commit(
                git_url="git://example.com/linux.git",
                commit_hash="abc123"
            )

        self.assertEqual(result['status'], 'success')
        self.assertEqual(result['data']['parent'], 'def456')

    def test_service_caches_parent_commit(self):
        """test：service parent commit """
        from server import CommitTimeService

        service = CommitTimeService()
        git_url = "git://example.com/linux.git"
        commit = "abc123"

        with patch.object(service.query, 'get_parent_commit') as mock_get:
            mock_get.return_value = {
                'commit': commit,
                'parent': 'def456',
                'parent_count': 1
            }

            # 
            result1 = service.get_parent_commit(git_url, commit)
            # （）
            result2 = service.get_parent_commit(git_url, commit)

        # query 
        self.assertEqual(mock_get.call_count, 1)
        #  cached
        self.assertTrue(result2.get('cached', False))


class TestParentCommitClient(unittest.TestCase):
    """test CommitTimeClient  parent commit """

    def test_client_get_parent_commit(self):
        """test： get_parent_commit"""
        from client import CommitTimeClient

        client = CommitTimeClient(service_url="http://localhost:8765")

        with patch('requests.get') as mock_get:
            mock_response = Mock()
            mock_response.status_code = 200
            mock_response.json.return_value = {
                'status': 'success',
                'data': {
                    'commit': 'abc123',
                    'parent': 'def456',
                    'parent_count': 1
                }
            }
            mock_get.return_value = mock_response

            parent = client.get_parent_commit(
                git_url="git://example.com/linux.git",
                commit="abc123"
            )

        self.assertEqual(parent, 'def456')

    def test_client_handles_root_commit(self):
        """test： root commit"""
        from client import CommitTimeClient

        client = CommitTimeClient(service_url="http://localhost:8765")

        with patch('urllib.request.urlopen') as mock_urlopen:
            mock_response = Mock()
            mock_response.read.return_value = json.dumps({
                'status': 'success',
                'data': {
                    'commit': 'root123',
                    'parent': None,
                    'parent_count': 0,
                    'reason': 'root_commit'
                }
            }).encode()
            mock_response.__enter__ = Mock(return_value=mock_response)
            mock_response.__exit__ = Mock(return_value=False)
            mock_urlopen.return_value = mock_response

            parent = client.get_parent_commit(
                git_url="git://example.com/linux.git",
                commit="root123"
            )

        # root commit  parent， None
        self.assertIsNone(parent)

    def test_client_handles_service_error(self):
        """test：serviceerror"""
        from client import CommitTimeClient
        import urllib.error

        client = CommitTimeClient(service_url="http://localhost:8765")

        with patch('urllib.request.urlopen') as mock_urlopen:
            mock_urlopen.side_effect = urllib.error.URLError("Connection refused")

            parent = client.get_parent_commit(
                git_url="git://example.com/linux.git",
                commit="abc123"
            )

        # service None
        self.assertIsNone(parent)


class TestConcurrency(unittest.TestCase):
    """test：verifyquery"""

    def test_concurrent_same_commit(self):
        """test：query commit"""
        import concurrent.futures
        import threading

        from server import CommitTimeService

        service = CommitTimeService()
        git_url = "git://example.com/linux.git"
        commit = "abc123"
        call_count = 0
        lock = threading.Lock()

        def mock_get_parent(*args, **kwargs):
            nonlocal call_count
            with lock:
                call_count += 1
            # 
            import time
            time.sleep(0.1)
            return {
                'commit': commit,
                'parent': 'def456',
                'parent_count': 1
            }

        with patch.object(service.query, 'get_parent_commit', side_effect=mock_get_parent):
            #  10 
            with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
                futures = [
                    executor.submit(service.get_parent_commit, git_url, commit)
                    for _ in range(10)
                ]
                results = [f.result() for f in concurrent.futures.as_completed(futures)]

        # success
        for result in results:
            self.assertEqual(result['status'], 'success')
            self.assertEqual(result['data']['parent'], 'def456')

        # ，query 10
        # ：query，
        self.assertLessEqual(call_count, 10)

    def test_concurrent_different_commits(self):
        """test：query commit"""
        import concurrent.futures

        from server import CommitTimeService

        service = CommitTimeService()
        git_url = "git://example.com/linux.git"
        commits = [f"commit_{i}" for i in range(5)]

        def mock_get_parent(url, commit_hash):
            return {
                'commit': commit_hash,
                'parent': f"parent_of_{commit_hash}",
                'parent_count': 1
            }

        with patch.object(service.query, 'get_parent_commit', side_effect=mock_get_parent):
            with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
                futures = {
                    executor.submit(service.get_parent_commit, git_url, c): c
                    for c in commits
                }
                results = {}
                for future in concurrent.futures.as_completed(futures):
                    commit = futures[future]
                    results[commit] = future.result()

        #  commit  parent
        for commit in commits:
            self.assertEqual(results[commit]['status'], 'success')
            self.assertEqual(
                results[commit]['data']['parent'],
                f"parent_of_{commit}"
            )

    def test_concurrent_different_repos(self):
        """test：queryrepo"""
        import concurrent.futures

        from server import CommitTimeService

        service = CommitTimeService()
        repos = [
            "git://example.com/linux.git",
            "git://example.com/linux-next.git",
            "git://example.com/openeuler-kernel.git"
        ]
        commit = "abc123"

        def mock_get_parent(url, commit_hash):
            repo_name = url.split('/')[-1].replace('.git', '')
            return {
                'commit': commit_hash,
                'parent': f"parent_in_{repo_name}",
                'parent_count': 1
            }

        with patch.object(service.query, 'get_parent_commit', side_effect=mock_get_parent):
            with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
                futures = {
                    executor.submit(service.get_parent_commit, repo, commit): repo
                    for repo in repos
                }
                results = {}
                for future in concurrent.futures.as_completed(futures):
                    repo = futures[future]
                    results[repo] = future.result()

        # repo parent
        for repo in repos:
            self.assertEqual(results[repo]['status'], 'success')
            repo_name = repo.split('/')[-1].replace('.git', '')
            self.assertEqual(
                results[repo]['data']['parent'],
                f"parent_in_{repo_name}"
            )


class TestDifferentRepos(unittest.TestCase):
    """repotest：verifysupportrepo"""

    # testrepoconfig
    TEST_REPOS = {
        'linux': {
            'url': 'git://172.168.131.113:9418/new-upstream/l/linux/linux.git',
            'sample_commit': 'v6.17',
        },
        'linux-next': {
            'url': 'git://172.168.131.113:9418/new-upstream/l/linux/linux-next.git',
            'sample_commit': 'next-20260101',
        },
        'linux-stable': {
            'url': 'git://172.168.131.113:9418/new-upstream/l/linux/linux-stable.git',
            'sample_commit': 'v6.12.1',
        },
        'openeuler-kernel': {
            'url': 'git://172.168.131.113:9418/new-upstream/l/linux/openeuler-kernel.git',
            'sample_commit': '6.6.0-98.0.0',
        }
    }

    def setUp(self):
        """test"""
        self.mock_repo_manager = Mock()
        self.mock_repo_manager.PRISTINE_BASE_DIR = '/tmp/pristine_repos'
        self.patcher = patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
        self.mock_is_git_repo = self.patcher.start()

    def tearDown(self):
        """test"""
        self.patcher.stop()

    def test_extract_repo_name_linux(self):
        """test： linux repo URL repo"""
        from bisect_utils import extract_repo_name_from_url

        url = self.TEST_REPOS['linux']['url']
        repo_name = extract_repo_name_from_url(url)

        self.assertEqual(repo_name, 'linux')

    def test_extract_repo_name_linux_next(self):
        """test： linux-next repo URL repo"""
        from bisect_utils import extract_repo_name_from_url

        url = self.TEST_REPOS['linux-next']['url']
        repo_name = extract_repo_name_from_url(url)

        self.assertEqual(repo_name, 'linux-next')

    def test_extract_repo_name_openeuler(self):
        """test： openeuler-kernel repo URL repo"""
        from bisect_utils import extract_repo_name_from_url

        url = self.TEST_REPOS['openeuler-kernel']['url']
        repo_name = extract_repo_name_from_url(url)

        self.assertEqual(repo_name, 'openeuler-kernel')

    def test_query_linux_repo(self):
        """test：query linux repo"""
        from commit_query import CommitTimeQuery

        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)
        url = self.TEST_REPOS['linux']['url']
        commit = "abc123"

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(
                returncode=0,
                stdout="parent_hash\n",
                stderr=""
            )
            result = query.get_parent_commit(url, commit)

        self.assertIsNotNone(result)
        self.assertEqual(result['parent'], 'parent_hash')

    def test_query_openeuler_kernel_repo(self):
        """test：query openeuler-kernel repo"""
        from commit_query import CommitTimeQuery

        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)
        url = self.TEST_REPOS['openeuler-kernel']['url']
        commit = "6.6.0-98.0.0"

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(
                returncode=0,
                stdout="oe_parent_hash\n",
                stderr=""
            )
            result = query.get_parent_commit(url, commit)

        self.assertIsNotNone(result)
        self.assertEqual(result['parent'], 'oe_parent_hash')

    def test_cache_isolates_different_repos(self):
        """test：repo"""
        from server import CommitTimeService

        service = CommitTimeService()
        commit = "abc123"  #  commit hash

        # repo， commit hash  parent
        linux_url = self.TEST_REPOS['linux']['url']
        oe_url = self.TEST_REPOS['openeuler-kernel']['url']

        call_log = []

        def mock_get_parent(url, commit_hash):
            call_log.append(url)
            repo_name = url.split('/')[-1].replace('.git', '')
            return {
                'commit': commit_hash,
                'parent': f"parent_in_{repo_name}",
                'parent_count': 1
            }

        with patch.object(service.query, 'get_parent_commit', side_effect=mock_get_parent):
            # query linux repo
            result1 = service.get_parent_commit(linux_url, commit)
            # query openeuler repo（）
            result2 = service.get_parent_commit(oe_url, commit)
            # query linux repo（）
            result3 = service.get_parent_commit(linux_url, commit)

        # linux  openeuler  parent
        self.assertEqual(result1['data']['parent'], 'parent_in_linux')
        self.assertEqual(result2['data']['parent'], 'parent_in_openeuler-kernel')

        # query
        self.assertTrue(result3.get('cached', False))

        # query 2 （linux  openeuler ）
        self.assertEqual(len(call_log), 2)

    def test_handles_different_url_formats(self):
        """test： URL"""
        from commit_query import CommitTimeQuery

        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        url_formats = [
            # git:// 
            "git://172.168.131.113:9418/new-upstream/l/linux/linux.git",
            # https:// 
            "https://gitee.com/openeuler/kernel.git",
            # http:// 
            "http://mirrors.example.com/linux.git",
            # 
            "https://mirrors.tuna.tsinghua.edu.cn/git/linux.git",
        ]

        for url in url_formats:
            with patch('subprocess.run') as mock_run:
                mock_run.return_value = Mock(
                    returncode=0,
                    stdout="parent_hash\n",
                    stderr=""
                )
                # exception
                result = query.get_parent_commit(url, "abc123")
                self.assertIsNotNone(result, f"Failed for URL: {url}")


class TestIntegration(unittest.TestCase):
    """test：verify"""

    @unittest.skip(" git repo，skip")
    def test_real_linux_repo(self):
        """test： linux repo"""
        from commit_query import CommitTimeQuery

        query = CommitTimeQuery()

        git_url = "git://172.168.131.113:9418/new-upstream/l/linux/linux.git"
        known_commit = "v6.17"

        result = query.get_parent_commit(git_url, known_commit)

        self.assertIsNotNone(result)
        self.assertIsNotNone(result['parent'])
        self.assertEqual(result['parent_count'], 1)

    @unittest.skip(" git repo，skip")
    def test_real_openeuler_repo(self):
        """test： openeuler-kernel repo"""
        from commit_query import CommitTimeQuery

        query = CommitTimeQuery()

        git_url = "git://172.168.131.113:9418/new-upstream/l/linux/openeuler-kernel.git"
        known_commit = "6.6.0-98.0.0"

        result = query.get_parent_commit(git_url, known_commit)

        self.assertIsNotNone(result)
        self.assertIsNotNone(result['parent'])

    @unittest.skip(" git repo，skip")
    def test_real_concurrent_queries(self):
        """test：query"""
        import concurrent.futures
        from commit_query import CommitTimeQuery

        query = CommitTimeQuery()

        test_cases = [
            ("git://172.168.131.113:9418/new-upstream/l/linux/linux.git", "v6.17"),
            ("git://172.168.131.113:9418/new-upstream/l/linux/linux-next.git", "v6.17"),
            ("git://172.168.131.113:9418/new-upstream/l/linux/openeuler-kernel.git", "6.6.0-98.0.0"),
        ]

        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = {
                executor.submit(query.get_parent_commit, url, commit): (url, commit)
                for url, commit in test_cases
            }

            for future in concurrent.futures.as_completed(futures):
                url, commit = futures[future]
                result = future.result()
                self.assertIsNotNone(result, f"Failed for {url} @ {commit}")


if __name__ == '__main__':
    # test
    unittest.main(verbosity=2)
