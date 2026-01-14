#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Parent Commit API 测试用例

TDD: 先写测试，再实现功能
"""

import unittest
import json
import os
import sys
from unittest.mock import Mock, patch, MagicMock

# 添加项目路径
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.environ.get('CCI_SRC', '/srv/cci'), 'container/bisect/lib'))


class TestParentCommitQuery(unittest.TestCase):
    """测试 CommitTimeQuery.get_parent_commit() 方法"""

    def setUp(self):
        """测试前准备"""
        # 使用 mock 避免实际 git 操作
        self.mock_repo_manager = Mock()
        # 设置 PRISTINE_BASE_DIR 为字符串，避免 os.path.join 失败
        self.mock_repo_manager.PRISTINE_BASE_DIR = '/tmp/pristine_repos'
        # Mock _is_git_repo 静态方法
        self.patcher = patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
        self.mock_is_git_repo = self.patcher.start()

    def tearDown(self):
        """测试后清理"""
        self.patcher.stop()

    # ==================== 正常情况 ====================

    def test_get_parent_of_normal_commit(self):
        """测试：查询普通 commit 的 parent"""
        # Given: 一个有 parent 的普通 commit
        git_url = "git://example.com/linux.git"
        commit = "abc123def456"
        expected_parent = "parent789xyz"

        # When: 调用 get_parent_commit
        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(
                returncode=0,
                stdout=f"{expected_parent}\n",
                stderr=""
            )
            result = query.get_parent_commit(git_url, commit)

        # Then: 返回正确的 parent commit
        self.assertIsNotNone(result)
        self.assertEqual(result['parent'], expected_parent)
        self.assertEqual(result['commit'], commit)
        self.assertEqual(result['parent_count'], 1)

    def test_get_parent_returns_full_hash(self):
        """测试：返回完整的 40 字符 hash"""
        git_url = "git://example.com/linux.git"
        commit = "abc123"  # 短 hash
        full_parent = "a" * 40  # 完整 hash

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

    # ==================== 边界情况 ====================

    def test_get_parent_of_root_commit(self):
        """测试：查询 root commit（无 parent）"""
        git_url = "git://example.com/linux.git"
        root_commit = "first_commit_hash"

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        with patch('subprocess.run') as mock_run:
            # 实际代码调用顺序：
            # 1. commit^@ 失败
            # 2. commit^1 失败
            # (fetch)
            # 3. commit^1 再次失败
            # 4. commit 本身检查成功（root commit 存在）
            mock_run.side_effect = [
                Mock(returncode=128, stdout="", stderr="fatal: no such object"),  # ^@
                Mock(returncode=128, stdout="", stderr="fatal: no such object"),  # ^1
                Mock(returncode=128, stdout="", stderr="fatal: no such object"),  # ^1 retry
                Mock(returncode=0, stdout=root_commit, stderr=""),  # commit 本身存在
            ]
            with patch.object(query, '_fetch_pristine_repo'):
                result = query.get_parent_commit(git_url, root_commit)

        # 应该返回明确的 "no_parent" 状态
        self.assertIsNotNone(result)
        self.assertEqual(result.get('parent'), None)
        self.assertEqual(result.get('parent_count'), 0)
        self.assertEqual(result.get('reason'), 'root_commit')

    def test_get_parent_of_merge_commit(self):
        """测试：查询 merge commit（多个 parent）"""
        git_url = "git://example.com/linux.git"
        merge_commit = "merge_commit_hash"
        parent1 = "parent1_hash"
        parent2 = "parent2_hash"

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        with patch('subprocess.run') as mock_run:
            # 实际代码只调用一次 commit^@，返回所有父提交（换行分隔）
            mock_run.return_value = Mock(
                returncode=0,
                stdout=f"{parent1}\n{parent2}\n",
                stderr=""
            )
            result = query.get_parent_commit(git_url, merge_commit)

        # 返回第一个 parent，并标明是 merge commit
        self.assertEqual(result['parent'], parent1)
        self.assertEqual(result['parent_count'], 2)

    def test_commit_not_found(self):
        """测试：commit 不存在"""
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
            # 模拟 fetch 后仍然找不到
            with patch.object(query, '_fetch_pristine_repo'):
                result = query.get_parent_commit(git_url, nonexistent_commit)

        self.assertIsNone(result)

    # ==================== 错误处理 ====================

    def test_invalid_git_url(self):
        """测试：无效的 git_url"""
        invalid_url = "not_a_valid_url"
        commit = "abc123"

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        result = query.get_parent_commit(invalid_url, commit)

        self.assertIsNone(result)

    def test_empty_commit_hash(self):
        """测试：空的 commit hash"""
        git_url = "git://example.com/linux.git"
        empty_commit = ""

        from commit_query import CommitTimeQuery
        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        result = query.get_parent_commit(git_url, empty_commit)

        self.assertIsNone(result)

    def test_timeout_handling(self):
        """测试：git 命令超时"""
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
    """测试 CommitTimeService 的 parent commit 功能"""

    def test_service_get_parent_commit_success(self):
        """测试：服务层成功获取 parent commit"""
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
        """测试：服务层缓存 parent commit 结果"""
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

            # 第一次调用
            result1 = service.get_parent_commit(git_url, commit)
            # 第二次调用（应该走缓存）
            result2 = service.get_parent_commit(git_url, commit)

        # query 只应该被调用一次
        self.assertEqual(mock_get.call_count, 1)
        # 第二次应该标记为 cached
        self.assertTrue(result2.get('cached', False))


class TestParentCommitClient(unittest.TestCase):
    """测试 CommitTimeClient 的 parent commit 功能"""

    def test_client_get_parent_commit(self):
        """测试：客户端调用 get_parent_commit"""
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
        """测试：客户端处理 root commit"""
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

        # root commit 没有 parent，返回 None
        self.assertIsNone(parent)

    def test_client_handles_service_error(self):
        """测试：客户端处理服务错误"""
        from client import CommitTimeClient
        import urllib.error

        client = CommitTimeClient(service_url="http://localhost:8765")

        with patch('urllib.request.urlopen') as mock_urlopen:
            mock_urlopen.side_effect = urllib.error.URLError("Connection refused")

            parent = client.get_parent_commit(
                git_url="git://example.com/linux.git",
                commit="abc123"
            )

        # 服务不可用时返回 None
        self.assertIsNone(parent)


class TestConcurrency(unittest.TestCase):
    """并发测试：验证多个请求同时查询"""

    def test_concurrent_same_commit(self):
        """测试：多个请求同时查询同一个 commit"""
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
            # 模拟耗时操作
            import time
            time.sleep(0.1)
            return {
                'commit': commit,
                'parent': 'def456',
                'parent_count': 1
            }

        with patch.object(service.query, 'get_parent_commit', side_effect=mock_get_parent):
            # 并发 10 个请求
            with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
                futures = [
                    executor.submit(service.get_parent_commit, git_url, commit)
                    for _ in range(10)
                ]
                results = [f.result() for f in concurrent.futures.as_completed(futures)]

        # 所有请求都应该成功
        for result in results:
            self.assertEqual(result['status'], 'success')
            self.assertEqual(result['data']['parent'], 'def456')

        # 由于缓存，实际查询次数应该远小于 10
        # 注意：第一个请求会触发查询，后续请求可能命中缓存
        self.assertLessEqual(call_count, 10)

    def test_concurrent_different_commits(self):
        """测试：多个请求同时查询不同 commit"""
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

        # 每个 commit 应该返回对应的 parent
        for commit in commits:
            self.assertEqual(results[commit]['status'], 'success')
            self.assertEqual(
                results[commit]['data']['parent'],
                f"parent_of_{commit}"
            )

    def test_concurrent_different_repos(self):
        """测试：多个请求同时查询不同仓库"""
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

        # 每个仓库应该返回对应的 parent
        for repo in repos:
            self.assertEqual(results[repo]['status'], 'success')
            repo_name = repo.split('/')[-1].replace('.git', '')
            self.assertEqual(
                results[repo]['data']['parent'],
                f"parent_in_{repo_name}"
            )


class TestDifferentRepos(unittest.TestCase):
    """不同仓库测试：验证支持多种内核仓库"""

    # 测试仓库配置
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
        """测试前准备"""
        self.mock_repo_manager = Mock()
        self.mock_repo_manager.PRISTINE_BASE_DIR = '/tmp/pristine_repos'
        self.patcher = patch('commit_query.SharedRepoManager._is_git_repo', return_value=True)
        self.mock_is_git_repo = self.patcher.start()

    def tearDown(self):
        """测试后清理"""
        self.patcher.stop()

    def test_extract_repo_name_linux(self):
        """测试：从 linux 仓库 URL 提取仓库名"""
        from bisect_utils import extract_repo_name_from_url

        url = self.TEST_REPOS['linux']['url']
        repo_name = extract_repo_name_from_url(url)

        self.assertEqual(repo_name, 'linux')

    def test_extract_repo_name_linux_next(self):
        """测试：从 linux-next 仓库 URL 提取仓库名"""
        from bisect_utils import extract_repo_name_from_url

        url = self.TEST_REPOS['linux-next']['url']
        repo_name = extract_repo_name_from_url(url)

        self.assertEqual(repo_name, 'linux-next')

    def test_extract_repo_name_openeuler(self):
        """测试：从 openeuler-kernel 仓库 URL 提取仓库名"""
        from bisect_utils import extract_repo_name_from_url

        url = self.TEST_REPOS['openeuler-kernel']['url']
        repo_name = extract_repo_name_from_url(url)

        self.assertEqual(repo_name, 'openeuler-kernel')

    def test_query_linux_repo(self):
        """测试：查询 linux 主仓库"""
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
        """测试：查询 openeuler-kernel 仓库"""
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
        """测试：缓存正确隔离不同仓库的结果"""
        from server import CommitTimeService

        service = CommitTimeService()
        commit = "abc123"  # 相同的 commit hash

        # 在不同仓库中，相同 commit hash 可能有不同的 parent
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
            # 查询 linux 仓库
            result1 = service.get_parent_commit(linux_url, commit)
            # 查询 openeuler 仓库（不应该命中缓存）
            result2 = service.get_parent_commit(oe_url, commit)
            # 再次查询 linux 仓库（应该命中缓存）
            result3 = service.get_parent_commit(linux_url, commit)

        # linux 和 openeuler 应该返回不同的 parent
        self.assertEqual(result1['data']['parent'], 'parent_in_linux')
        self.assertEqual(result2['data']['parent'], 'parent_in_openeuler-kernel')

        # 第三次查询应该命中缓存
        self.assertTrue(result3.get('cached', False))

        # 实际查询只应该有 2 次（linux 和 openeuler 各一次）
        self.assertEqual(len(call_log), 2)

    def test_handles_different_url_formats(self):
        """测试：处理不同格式的 URL"""
        from commit_query import CommitTimeQuery

        query = CommitTimeQuery(repo_manager=self.mock_repo_manager)

        url_formats = [
            # git:// 协议
            "git://172.168.131.113:9418/new-upstream/l/linux/linux.git",
            # https:// 协议
            "https://gitee.com/openeuler/kernel.git",
            # http:// 协议
            "http://mirrors.example.com/linux.git",
            # 清华镜像
            "https://mirrors.tuna.tsinghua.edu.cn/git/linux.git",
        ]

        for url in url_formats:
            with patch('subprocess.run') as mock_run:
                mock_run.return_value = Mock(
                    returncode=0,
                    stdout="parent_hash\n",
                    stderr=""
                )
                # 不应该抛出异常
                result = query.get_parent_commit(url, "abc123")
                self.assertIsNotNone(result, f"Failed for URL: {url}")


class TestIntegration(unittest.TestCase):
    """集成测试：验证完整流程"""

    @unittest.skip("需要实际的 git 仓库，跳过")
    def test_real_linux_repo(self):
        """测试：使用真实 linux 仓库"""
        from commit_query import CommitTimeQuery

        query = CommitTimeQuery()

        git_url = "git://172.168.131.113:9418/new-upstream/l/linux/linux.git"
        known_commit = "v6.17"

        result = query.get_parent_commit(git_url, known_commit)

        self.assertIsNotNone(result)
        self.assertIsNotNone(result['parent'])
        self.assertEqual(result['parent_count'], 1)

    @unittest.skip("需要实际的 git 仓库，跳过")
    def test_real_openeuler_repo(self):
        """测试：使用真实 openeuler-kernel 仓库"""
        from commit_query import CommitTimeQuery

        query = CommitTimeQuery()

        git_url = "git://172.168.131.113:9418/new-upstream/l/linux/openeuler-kernel.git"
        known_commit = "6.6.0-98.0.0"

        result = query.get_parent_commit(git_url, known_commit)

        self.assertIsNotNone(result)
        self.assertIsNotNone(result['parent'])

    @unittest.skip("需要实际的 git 仓库，跳过")
    def test_real_concurrent_queries(self):
        """测试：真实环境并发查询"""
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
    # 运行测试
    unittest.main(verbosity=2)
