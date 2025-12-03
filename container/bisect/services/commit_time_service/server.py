#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Commit Time Service - HTTP 服务

提供 REST API 查询 Git commit 时间信息
"""

import os
import sys
import json
import time
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from typing import Dict, Any

# 添加项目路径
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
    """Commit 时间查询服务"""

    def __init__(self, cache_size: int = 10000, cache_ttl: int = 86400):
        """
        初始化服务

        Args:
            cache_size: 缓存大小
            cache_ttl: 缓存过期时间（秒）
        """
        self.query = CommitTimeQuery()
        self.cache = CommitTimeCache(max_size=cache_size, ttl=cache_ttl)
        self.request_count = 0
        self.cache_hit_count = 0
        self.start_time = time.time()

    def get_commit_time(self, git_url: str, commit_hash: str) -> Dict[str, Any]:
        """
        获取 commit 时间信息

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash

        Returns:
            查询结果字典
        """
        self.request_count += 1

        # 先查缓存
        cached_info = self.cache.get_info(git_url, commit_hash)
        if cached_info:
            self.cache_hit_count += 1
            return {
                'status': 'success',
                'cached': True,
                'data': cached_info
            }

        # 缓存未命中，查询 git
        info = self.query.get_commit_info(git_url, commit_hash)
        if info:
            # 存入缓存
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
        检查 commit 是否超过指定天数

        Args:
            git_url: Git 仓库 URL
            commit_hash: Commit hash
            max_age_days: 最大天数

        Returns:
            检查结果字典
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

    def get_stats(self) -> Dict[str, Any]:
        """获取服务统计信息"""
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
    """HTTP 请求处理器"""

    # 类变量，由服务器设置
    service = None

    def do_GET(self):
        """处理 GET 请求"""
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        try:
            if path == '/api/v1/commit/time':
                self.handle_commit_time(params)
            elif path == '/api/v1/commit/check':
                self.handle_commit_check(params)
            elif path == '/api/v1/stats':
                self.handle_stats()
            elif path == '/health':
                self.handle_health()
            else:
                self.send_error_response(404, 'Not Found')

        except Exception as e:
            logger.error(f"Request error: {str(e)}")
            self.send_error_response(500, str(e))

    def handle_commit_time(self, params: Dict):
        """处理 commit 时间查询"""
        git_url = params.get('repo', [None])[0]
        commit = params.get('commit', [None])[0]

        if not git_url or not commit:
            self.send_error_response(400, 'Missing required parameters: repo, commit')
            return

        result = self.service.get_commit_time(git_url, commit)
        self.send_json_response(result)

    def handle_commit_check(self, params: Dict):
        """处理 commit 年龄检查"""
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

    def handle_stats(self):
        """处理统计信息请求"""
        stats = self.service.get_stats()
        self.send_json_response(stats)

    def handle_health(self):
        """处理健康检查"""
        self.send_json_response({'status': 'healthy'})

    def send_json_response(self, data: Dict, status_code: int = 200):
        """发送 JSON 响应"""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

    def send_error_response(self, status_code: int, message: str):
        """发送错误响应"""
        self.send_json_response({
            'status': 'error',
            'error': message
        }, status_code)

    def log_message(self, format, *args):
        """自定义日志格式"""
        logger.info(f"{self.address_string()} - {format % args}")


def run_server(host: str = '0.0.0.0', port: int = 8765,
               cache_size: int = 10000, cache_ttl: int = 86400):
    """
    启动 HTTP 服务器

    Args:
        host: 绑定地址
        port: 端口号
        cache_size: 缓存大小
        cache_ttl: 缓存过期时间
    """
    # 创建服务实例
    service = CommitTimeService(cache_size=cache_size, cache_ttl=cache_ttl)

    # 设置请求处理器的服务实例
    RequestHandler.service = service

    # 创建服务器
    server = HTTPServer((host, port), RequestHandler)

    logger.info(f"Commit Time Service started | {host}:{port}")
    logger.info(f"Cache size: {cache_size} | TTL: {cache_ttl}s")
    logger.info("Endpoints:")
    logger.info(f"  GET /api/v1/commit/time?repo=<url>&commit=<hash>")
    logger.info(f"  GET /api/v1/commit/check?repo=<url>&commit=<hash>&max_age_days=365")
    logger.info(f"  GET /api/v1/stats")
    logger.info(f"  GET /health")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Server shutting down...")
        server.shutdown()


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='Commit Time Service')
    parser.add_argument('--host', default='0.0.0.0', help='Bind address')
    parser.add_argument('--port', type=int, default=8765, help='Port number')
    parser.add_argument('--cache-size', type=int, default=10000, help='Cache size')
    parser.add_argument('--cache-ttl', type=int, default=86400, help='Cache TTL in seconds')

    args = parser.parse_args()

    # 确保必要的环境变量
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
