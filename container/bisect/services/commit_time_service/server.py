#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Commit Time Service - HTTP service

 REST API query Git commit 
"""

import os
import sys
import json
import time
import signal
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from typing import Dict, Any

# 
lib_path = os.path.join(os.environ.get('CCI_SRC', '/srv/cci'), 'container/bisect/lib')
if lib_path not in sys.path:
    sys.path.insert(0, lib_path)

service_path = os.path.dirname(__file__)
if service_path and service_path not in sys.path:
    sys.path.insert(0, service_path)

from commit_query import CommitTimeQuery
from cache import CommitTimeCache
from log_config import logger


class CommitTimeService:
    """Commit queryservice"""

    def __init__(self, cache_size: int = 10000, cache_ttl: int = 86400):
        """
        initializeservice

        Args:
            cache_size: 
            cache_ttl: （）
        """
        self.query = CommitTimeQuery()
        self.cache = CommitTimeCache(max_size=cache_size, ttl=cache_ttl)
        self.request_count = 0
        self.cache_hit_count = 0
        self.start_time = time.time()

    def get_commit_time(self, git_url: str, commit_hash: str) -> Dict[str, Any]:
        """
        get commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash

        Returns:
            querydict
        """
        self.request_count += 1

        # 
        cached_info = self.cache.get_info(git_url, commit_hash)
        if cached_info:
            self.cache_hit_count += 1
            return {
                'status': 'success',
                'cached': True,
                'data': cached_info
            }

        # ，query git
        info = self.query.get_commit_info(git_url, commit_hash)
        if info:
            # 
            self.cache.set_info(git_url, commit_hash, info)
            return {
                'status': 'success',
                'cached': False,
                'data': info
            }
        else:
            return {
                'status': 'error',
                'error': 'Commit not found or query failed',
                'git_url': git_url,
                'commit': commit_hash
            }

    def check_commit_age(self, git_url: str, commit_hash: str, max_age_days: int = 365) -> Dict[str, Any]:
        """
        check commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash
            max_age_days: 

        Returns:
            checkdict
        """
        result = self.get_commit_time(git_url, commit_hash)

        if result['status'] != 'success':
            return result

        age_days = result['data']['age_days']
        is_too_old = age_days > max_age_days

        return {
            'status': 'success',
            'cached': result['cached'],
            'data': {
                'commit': result['data']['commit'],
                'age_days': age_days,
                'max_age_days': max_age_days,
                'is_too_old': is_too_old
            }
        }

    def batch_check_commits(self, items: list, max_age_days: int = 365,
                             min_kernel_version: str = None) -> Dict[str, Any]:
        """
        check commit ，

        Args:
            items: list， {'git_url': ..., 'commit': ..., 'job_id': ...}
            max_age_days: 
            min_kernel_version: （ "5.10"）， None check

        Returns:
            check
        """
        results = []
        too_old_job_ids = set()
        old_branch_job_ids = set()
        valid_job_ids = set()
        errors = []

        for item in items:
            git_url = item.get('git_url')
            commit_hash = item.get('commit')
            job_id = item.get('job_id')

            if not git_url or not commit_hash or not job_id:
                errors.append({'job_id': job_id, 'error': 'missing required fields'})
                continue

            result = self.get_commit_time(git_url, commit_hash)
            filter_reason = None
            base_tag = None

            # check commit 
            if result['status'] != 'success':
                # queryfailed（）
                valid_job_ids.add(job_id)
                continue

            age_days = result['data']['age_days']
            is_too_old = age_days > max_age_days

            if is_too_old:
                too_old_job_ids.add(job_id)
                filter_reason = f'commit_too_old (>{max_age_days} days)'
            elif min_kernel_version:
                # check
                is_old_branch, base_tag, _ = self.query.is_commit_on_old_branch(
                    git_url, commit_hash, min_kernel_version
                )
                if is_old_branch:
                    old_branch_job_ids.add(job_id)
                    filter_reason = f'old_branch ({base_tag} < v{min_kernel_version})'
                else:
                    valid_job_ids.add(job_id)
            else:
                valid_job_ids.add(job_id)

            results.append({
                'job_id': job_id,
                'commit': commit_hash[:12] if len(commit_hash) > 12 else commit_hash,
                'age_days': age_days,
                'is_too_old': is_too_old,
                'base_tag': base_tag,
                'filter_reason': filter_reason
            })

        #  job_ids
        filtered_job_ids = too_old_job_ids | old_branch_job_ids

        return {
            'status': 'success',
            'data': {
                'total': len(items),
                'checked': len(results),
                'too_old_count': len(too_old_job_ids),
                'old_branch_count': len(old_branch_job_ids),
                'valid_count': len(valid_job_ids),
                'too_old_job_ids': list(filtered_job_ids),  # 
                'old_branch_job_ids': list(old_branch_job_ids),
                'valid_job_ids': list(valid_job_ids),
                'max_age_days': max_age_days,
                'min_kernel_version': min_kernel_version,
                'details': results,
                'errors': errors
            }
        }

    def check_branch_version(self, git_url: str, commit_hash: str,
                              min_version: str = "5.10") -> Dict[str, Any]:
        """
        check commit 

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash
            min_version: support

        Returns:
            checkdict
        """
        is_old, base_tag, version = self.query.is_commit_on_old_branch(
            git_url, commit_hash, min_version
        )

        if is_old is None:
            return {
                'status': 'error',
                'error': 'Cannot determine branch version',
                'base_tag': base_tag
            }

        return {
            'status': 'success',
            'data': {
                'commit': commit_hash,
                'base_tag': base_tag,
                'version': list(version) if version else None,
                'min_version': min_version,
                'is_old_branch': is_old
            }
        }

    def check_ancestor(self, git_url: str, ancestor_commit: str,
                       descendant_commit: str) -> Dict[str, Any]:
        """
        Check if ancestor_commit is an ancestor of descendant_commit.

        Args:
            git_url: Git repository URL
            ancestor_commit: The potential ancestor commit hash
            descendant_commit: The potential descendant commit hash

        Returns:
            Result dict with is_ancestor boolean
        """
        self.request_count += 1

        try:
            is_ancestor = self.query.is_ancestor(git_url, ancestor_commit, descendant_commit)
            if is_ancestor is None:
                return {
                    'status': 'error',
                    'error': 'Cannot determine ancestor relationship',
                    'error_code': 'unable_to_determine_ancestor',
                    'retryable': True,
                    'git_url': git_url,
                    'ancestor': ancestor_commit,
                    'descendant': descendant_commit
                }
            return {
                'status': 'success',
                'data': {
                    'is_ancestor': is_ancestor,
                    'ancestor': ancestor_commit,
                    'descendant': descendant_commit
                }
            }
        except Exception as e:
            return {
                'status': 'error',
                'error': f'Ancestor check failed: {str(e)}',
                'git_url': git_url,
                'ancestor': ancestor_commit,
                'descendant': descendant_commit
            }

    def get_parent_commit(self, git_url: str, commit_hash: str) -> Dict[str, Any]:
        """
        get commit submit

        Args:
            git_url: Git repo URL
            commit_hash: Commit hash

        Returns:
            querydict，：
            {
                'status': 'success' | 'error',
                'cached': bool,
                'data': {
                    'commit': str,
                    'parent': str | None,
                    'parent_count': int,
                    'reason': str  # 
                }
            }
        """
        self.request_count += 1

        # ：parent commit ，
        cache_key = f"parent:{git_url}:{commit_hash}"

        # 
        cached_data = self.cache.get(cache_key)
        if cached_data:
            self.cache_hit_count += 1
            return {
                'status': 'success',
                'cached': True,
                'data': cached_data
            }

        # ，query git
        if hasattr(self.query, 'get_parent_commit_detailed'):
            detailed = self.query.get_parent_commit_detailed(git_url, commit_hash)
            if detailed.get('status') == 'success':
                data = detailed.get('data', {})
                self.cache.set(cache_key, data)
                return {
                    'status': 'success',
                    'cached': False,
                    'data': data
                }
            return {
                'status': 'error',
                'error': detailed.get('error', 'Failed to get parent commit'),
                'error_code': detailed.get('error_code', 'unknown'),
                'retryable': bool(detailed.get('retryable', True)),
                'git_url': git_url,
                'commit': commit_hash
            }

        # Backward-compatible path for older query implementations.
        result = self.query.get_parent_commit(git_url, commit_hash)
        if result:
            self.cache.set(cache_key, result)
            return {
                'status': 'success',
                'cached': False,
                'data': result
            }
        return {
            'status': 'error',
            'error': 'Failed to get parent commit',
            'error_code': 'unknown',
            'retryable': True,
            'git_url': git_url,
            'commit': commit_hash
        }

    def batch_check_ancestor(self, git_url: str,
                             pairs: list) -> Dict[str, Any]:
        """
        Batch check ancestor relationships for multiple commit pairs.

        Runs checks in parallel using thread pool for better throughput.

        Args:
            git_url: Git repository URL
            pairs: List of {'ancestor': str, 'descendant': str}

        Returns:
            Result dict with per-pair results
        """
        from concurrent.futures import ThreadPoolExecutor, as_completed

        self.request_count += 1
        if not pairs:
            return {'status': 'success', 'data': {'git_url': git_url, 'total': 0, 'results': []}}

        results = [None] * len(pairs)
        max_workers = min(len(pairs), 8)

        def check_one(index, ancestor, descendant):
            is_anc = self.query.is_ancestor(git_url, ancestor, descendant)
            return index, is_anc

        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = []
            for i, pair in enumerate(pairs):
                ancestor = pair.get('ancestor', '')
                descendant = pair.get('descendant', '')
                futures.append(pool.submit(check_one, i, ancestor, descendant))

            for future in as_completed(futures):
                try:
                    idx, is_anc = future.result(timeout=120)
                    results[idx] = is_anc
                except Exception:
                    pass  # results[idx] stays None

        return {
            'status': 'success',
            'data': {
                'git_url': git_url,
                'total': len(pairs),
                'results': [
                    {
                        'ancestor': pairs[i].get('ancestor', ''),
                        'descendant': pairs[i].get('descendant', ''),
                        'is_ancestor': results[i]
                    }
                    for i in range(len(pairs))
                ]
            }
        }

    def get_stats(self) -> Dict[str, Any]:
        """getservicestats"""
        uptime = time.time() - self.start_time
        cache_stats = self.cache.get_stats()

        return {
            'uptime_seconds': int(uptime),
            'total_requests': self.request_count,
            'cache_hits': self.cache_hit_count,
            'cache_hit_rate': self.cache_hit_count / self.request_count if self.request_count > 0 else 0,
            'cache_stats': cache_stats
        }


class RequestHandler(BaseHTTPRequestHandler):
    """HTTP """

    # ，service
    service = None

    def do_GET(self):
        """ GET """
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        try:
            if path == '/api/v1/commit/time':
                self.handle_commit_time(params)
            elif path == '/api/v1/commit/check':
                self.handle_commit_check(params)
            elif path == '/api/v1/commit/branch_check':
                self.handle_branch_check(params)
            elif path == '/api/v1/commit/is-ancestor':
                self.handle_is_ancestor(params)
            elif path == '/api/v1/commit/parent':
                self.handle_parent_commit(params)
            elif path == '/api/v1/stats':
                self.handle_stats()
            elif path == '/health':
                self.handle_health()
            else:
                self.send_error_response(404, 'Not Found')

        except Exception as e:
            logger.error(f"Request error: {str(e)}")
            self.send_error_response(500, str(e))

    def do_POST(self):
        """ POST """
        parsed = urlparse(self.path)
        path = parsed.path

        try:
            if path == '/api/v1/commit/batch_check':
                self.handle_batch_check()
            elif path == '/api/v1/commit/batch_is_ancestor':
                self.handle_batch_is_ancestor()
            else:
                self.send_error_response(404, 'Not Found')

        except Exception as e:
            logger.error(f"POST request error: {str(e)}")
            self.send_error_response(500, str(e))

    def handle_commit_time(self, params: Dict):
        """ commit query"""
        git_url = params.get('repo', [None])[0]
        commit = params.get('commit', [None])[0]

        if not git_url or not commit:
            self.send_error_response(400, 'Missing required parameters: repo, commit')
            return

        result = self.service.get_commit_time(git_url, commit)
        self.send_json_response(result)

    def handle_commit_check(self, params: Dict):
        """ commit check"""
        git_url = params.get('repo', [None])[0]
        commit = params.get('commit', [None])[0]
        max_age = params.get('max_age_days', ['365'])[0]

        if not git_url or not commit:
            self.send_error_response(400, 'Missing required parameters: repo, commit')
            return

        try:
            max_age_days = int(max_age)
        except ValueError:
            self.send_error_response(400, 'Invalid max_age_days parameter')
            return

        result = self.service.check_commit_age(git_url, commit, max_age_days)
        self.send_json_response(result)

    def handle_branch_check(self, params: Dict):
        """check"""
        git_url = params.get('repo', [None])[0]
        commit = params.get('commit', [None])[0]
        min_version = params.get('min_version', ['5.10'])[0]

        if not git_url or not commit:
            self.send_error_response(400, 'Missing required parameters: repo, commit')
            return

        result = self.service.check_branch_version(git_url, commit, min_version)
        self.send_json_response(result)

    def handle_is_ancestor(self, params: Dict):
        """Handle ancestor check request"""
        git_url = params.get('repo', [None])[0]
        ancestor = params.get('ancestor', [None])[0]
        descendant = params.get('descendant', [None])[0]

        if not git_url or not ancestor or not descendant:
            self.send_error_response(400, 'Missing required parameters: repo, ancestor, descendant')
            return

        result = self.service.check_ancestor(git_url, ancestor, descendant)
        self.send_json_response(result)

    def handle_parent_commit(self, params: Dict):
        """ parent commit query"""
        git_url = params.get('repo', [None])[0]
        commit = params.get('commit', [None])[0]

        if not git_url or not commit:
            self.send_error_response(400, 'Missing required parameters: repo, commit')
            return

        result = self.service.get_parent_commit(git_url, commit)
        self.send_json_response(result)

    def handle_batch_is_ancestor(self):
        """Handle batch ancestor check"""
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length == 0:
            self.send_error_response(400, 'Missing request body')
            return

        body = self.rfile.read(content_length)
        try:
            data = json.loads(body.decode('utf-8'))
        except json.JSONDecodeError as e:
            self.send_error_response(400, f'Invalid JSON: {str(e)}')
            return

        git_url = data.get('git_url', '')
        pairs = data.get('pairs', [])

        if not git_url or not pairs:
            self.send_error_response(400, 'Missing git_url or pairs')
            return

        if not isinstance(pairs, list):
            self.send_error_response(400, 'pairs must be a list')
            return

        result = self.service.batch_check_ancestor(git_url, pairs)
        self.send_json_response(result)

    def handle_batch_check(self):
        """ commit check"""
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length == 0:
            self.send_error_response(400, 'Missing request body')
            return

        body = self.rfile.read(content_length)
        try:
            data = json.loads(body.decode('utf-8'))
        except json.JSONDecodeError as e:
            self.send_error_response(400, f'Invalid JSON: {str(e)}')
            return

        items = data.get('items', [])
        max_age_days = data.get('max_age_days', 365)
        min_kernel_version = data.get('min_kernel_version')  # 

        if not items:
            self.send_error_response(400, 'Missing items in request body')
            return

        if not isinstance(items, list):
            self.send_error_response(400, 'items must be a list')
            return

        result = self.service.batch_check_commits(items, max_age_days, min_kernel_version)
        self.send_json_response(result)

    def handle_stats(self):
        """stats"""
        stats = self.service.get_stats()
        self.send_json_response(stats)

    def handle_health(self):
        """check"""
        self.send_json_response({'status': 'healthy'})

    def send_json_response(self, data: Dict, status_code: int = 200):
        """ JSON """
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

    def send_error_response(self, status_code: int, message: str):
        """error"""
        self.send_json_response({
            'status': 'error',
            'error': message
        }, status_code)

    def log_message(self, format, *args):
        """log"""
        logger.info(f"{self.address_string()} - {format % args}")


def run_server(host: str = '0.0.0.0', port: int = 8765,
               cache_size: int = 10000, cache_ttl: int = 86400):
    """
     HTTP service

    Args:
        host: 
        port: 
        cache_size: 
        cache_ttl: 
    """
    # createserviceinstance
    service = CommitTimeService(cache_size=cache_size, cache_ttl=cache_ttl)

    # serviceinstance
    RequestHandler.service = service

    # createservice
    server = HTTPServer((host, port), RequestHandler)

    # ，
    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}, shutting down...")
        server.shutdown()

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    logger.info(f"Commit Time Service started | {host}:{port}")
    logger.info(f"Cache size: {cache_size} | TTL: {cache_ttl}s")
    logger.info("Endpoints:")
    logger.info(f"  GET  /api/v1/commit/time?repo=<url>&commit=<hash>")
    logger.info(f"  GET  /api/v1/commit/check?repo=<url>&commit=<hash>&max_age_days=365")
    logger.info(f"  GET  /api/v1/commit/is-ancestor?repo=<url>&ancestor=<hash>&descendant=<hash>")
    logger.info(f"  GET  /api/v1/commit/parent?repo=<url>&commit=<hash>")
    logger.info(f"  POST /api/v1/commit/batch_check  (body: {{items: [...], max_age_days: 365}})")
    logger.info(f"  POST /api/v1/commit/batch_is_ancestor  (body: {{git_url: ..., pairs: [{{ancestor: ..., descendant: ...}}]}})")
    logger.info(f"  GET  /api/v1/stats")
    logger.info(f"  GET  /health")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        logger.info("Server stopped")
        server.server_close()


def main():
    """main function"""
    parser = argparse.ArgumentParser(description='Commit Time Service')
    parser.add_argument('--host', default='0.0.0.0', help='Bind address')
    parser.add_argument('--port', type=int, default=8765, help='Port number')
    parser.add_argument('--cache-size', type=int, default=10000, help='Cache size')
    parser.add_argument('--cache-ttl', type=int, default=86400, help='Cache TTL in seconds')

    args = parser.parse_args()

    # 
    if 'CCI_SRC' not in os.environ:
        os.environ['CCI_SRC'] = '/srv/cci'
    if 'WORK_DIR' not in os.environ:
        os.environ['WORK_DIR'] = '/tmp'
    if 'LKP_SRC' not in os.environ:
        os.environ['LKP_SRC'] = '/srv/lkp'

    run_server(
        host=args.host,
        port=args.port,
        cache_size=args.cache_size,
        cache_ttl=args.cache_ttl
    )


if __name__ == '__main__':
    main()
