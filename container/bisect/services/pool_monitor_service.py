#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
仓库池监控 API 服务

提供 REST API 接口来管理和监控仓库池：
- GET /api/pool/status - 获取池状态
- POST /api/pool/cleanup - 触发清理
- GET /api/pool/stats - 获取统计信息
- POST /api/pool/verify - 验证一致性
- GET /api/pool/instances/{repo_name} - 获取特定仓库的实例信息
"""

import os
import sys
import time
import json
import threading
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from flask import Flask, jsonify, request
from flask_cors import CORS
import schedule

sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lib'))
from log_config import logger
from repo_manager import SharedRepoManager


class PoolMonitorService:
    """仓库池监控服务"""

    # 配置参数
    MAX_HOLD_SECONDS = 10 * 3600  # 10小时
    WARNING_THRESHOLD_SECONDS = 8 * 3600  # 8小时告警
    CHECK_INTERVAL_MINUTES = 10  # 10分钟检查一次

    def __init__(self):
        self.repo_manager = SharedRepoManager()
        self.stats = {
            'service_start_time': time.time(),
            'last_check_time': 0,
            'total_checks': 0,
            'total_warnings': 0,
            'total_cleaned': 0,
            'last_cleanup_time': 0,
            'last_cleanup_count': 0
        }
        self.monitor_thread = None
        self.running = False

    def start_monitor(self):
        """启动后台监控线程"""
        if self.running:
            return {"status": "already running"}

        self.running = True
        self.monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self.monitor_thread.start()
        logger.info("Pool monitor thread started")
        return {"status": "started"}

    def stop_monitor(self):
        """停止后台监控"""
        self.running = False
        if self.monitor_thread:
            self.monitor_thread.join(timeout=5)
        logger.info("Pool monitor thread stopped")
        return {"status": "stopped"}

    def _monitor_loop(self):
        """监控循环"""
        schedule.every(self.CHECK_INTERVAL_MINUTES).minutes.do(self._periodic_check)

        while self.running:
            schedule.run_pending()
            time.sleep(60)  # 每分钟检查一次调度

    def _periodic_check(self):
        """定期检查"""
        try:
            logger.info("Starting periodic pool check...")
            result = self.check_and_cleanup(dry_run=False, auto_cleanup=True)
            self.stats['last_check_time'] = time.time()
            self.stats['total_checks'] += 1
            logger.info(f"Periodic check completed: {result['summary']}")
        except Exception as e:
            logger.error(f"Periodic check failed: {str(e)}")

    def get_pool_status(self) -> Dict:
        """获取池状态"""
        try:
            pool_stats = self.repo_manager.get_pool_stats()
            current_time = time.time()

            # 分析每个仓库的状态
            detailed_status = {}
            total_in_use = 0
            total_available = 0
            total_instances = 0
            long_running = []

            with self.repo_manager.pool_lock:
                for repo_name, state in self.repo_manager.pool_state.items():
                    repo_info = {
                        'total': state['total'],
                        'available': len(state['available']),
                        'in_use': len(state['in_use']),
                        'in_use_details': []
                    }

                    total_instances += state['total']
                    total_available += len(state['available'])
                    total_in_use += len(state['in_use'])

                    # 收集使用中的实例详情
                    for iid, info in state['in_use'].items():
                        acquired_at = info.get('acquired_at', 0)
                        held_duration = current_time - acquired_at if acquired_at else 0
                        held_hours = held_duration / 3600

                        instance_info = {
                            'instance_id': iid,
                            'task_id': info.get('task_id'),
                            'held_hours': round(held_hours, 2),
                            'status': 'warning' if held_duration > self.WARNING_THRESHOLD_SECONDS else 'normal'
                        }

                        repo_info['in_use_details'].append(instance_info)

                        if held_duration > self.WARNING_THRESHOLD_SECONDS:
                            long_running.append({
                                'repo': repo_name,
                                'instance_id': iid,
                                'task_id': info.get('task_id'),
                                'held_hours': round(held_hours, 2)
                            })

                    # 按占用时间排序
                    repo_info['in_use_details'].sort(key=lambda x: x['held_hours'], reverse=True)
                    detailed_status[repo_name] = repo_info

            return {
                'status': 'ok',
                'timestamp': datetime.now().isoformat(),
                'summary': {
                    'total_instances': total_instances,
                    'total_in_use': total_in_use,
                    'total_available': total_available,
                    'utilization_rate': round(total_in_use / max(total_instances, 1) * 100, 2)
                },
                'repositories': detailed_status,
                'warnings': long_running,
                'service_stats': self.stats
            }

        except Exception as e:
            logger.error(f"Failed to get pool status: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def check_and_cleanup(self, dry_run: bool = True,
                         max_hours: Optional[float] = None,
                         auto_cleanup: bool = False) -> Dict:
        """检查并清理超时实例"""
        max_hold_seconds = (max_hours * 3600) if max_hours else self.MAX_HOLD_SECONDS
        current_time = time.time()

        warnings = []
        cleaned = []
        errors = []

        try:
            with self.repo_manager.pool_lock:
                for repo_name, state in self.repo_manager.pool_state.items():
                    for instance_id, info in list(state['in_use'].items()):
                        task_id = info.get('task_id')
                        acquired_at = info.get('acquired_at', 0)

                        if not acquired_at:
                            continue

                        held_duration = current_time - acquired_at
                        held_hours = held_duration / 3600

                        # 记录警告
                        if held_duration > self.WARNING_THRESHOLD_SECONDS:
                            warnings.append({
                                'repo': repo_name,
                                'instance_id': instance_id,
                                'task_id': task_id,
                                'held_hours': round(held_hours, 2)
                            })
                            self.stats['total_warnings'] += 1

                        # 清理超时实例
                        if auto_cleanup and held_duration > max_hold_seconds:
                            if dry_run:
                                cleaned.append({
                                    'repo': repo_name,
                                    'instance_id': instance_id,
                                    'task_id': task_id,
                                    'held_hours': round(held_hours, 2),
                                    'action': 'would_clean'
                                })
                            else:
                                try:
                                    # 执行实际清理
                                    workspace_path = os.path.join(
                                        self.repo_manager.REPO_BASE_DIR,
                                        str(task_id),
                                        repo_name
                                    )

                                    pool_path = os.path.join(
                                        self.repo_manager.POOL_BASE_DIR,
                                        f"{repo_name}-{instance_id}"
                                    )

                                    # 从 in_use 中移除
                                    del state['in_use'][instance_id]

                                    # 尝试恢复到池
                                    if os.path.exists(workspace_path):
                                        self.repo_manager._cleanup_repo(workspace_path)
                                        os.rename(workspace_path, pool_path)
                                        state['available'].append(instance_id)
                                        action = 'recovered'
                                    else:
                                        # 幽灵实例
                                        if state['total'] > 0:
                                            state['total'] -= 1
                                        action = 'removed_ghost'

                                    cleaned.append({
                                        'repo': repo_name,
                                        'instance_id': instance_id,
                                        'task_id': task_id,
                                        'held_hours': round(held_hours, 2),
                                        'action': action
                                    })

                                    self.stats['total_cleaned'] += 1

                                    logger.info(f"Cleaned: {repo_name}-{instance_id} ({action})")

                                except Exception as e:
                                    errors.append({
                                        'repo': repo_name,
                                        'instance_id': instance_id,
                                        'error': str(e)
                                    })
                                    logger.error(f"Failed to clean {repo_name}-{instance_id}: {str(e)}")

                # 通知等待线程
                if cleaned and not dry_run:
                    for repo_name in set(c['repo'] for c in cleaned):
                        if repo_name in self.repo_manager.pool_conditions:
                            condition = self.repo_manager.pool_conditions[repo_name]
                            condition.notify_all()

            # 更新统计
            if cleaned and not dry_run:
                self.stats['last_cleanup_time'] = current_time
                self.stats['last_cleanup_count'] = len(cleaned)

            return {
                'status': 'ok',
                'timestamp': datetime.now().isoformat(),
                'dry_run': dry_run,
                'summary': {
                    'warnings': len(warnings),
                    'cleaned': len(cleaned),
                    'errors': len(errors)
                },
                'warnings': warnings[:10],  # 限制返回数量
                'cleaned': cleaned[:10],
                'errors': errors
            }

        except Exception as e:
            logger.error(f"Check and cleanup failed: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def verify_consistency(self) -> Dict:
        """验证池一致性"""
        try:
            inconsistencies = self.repo_manager.verify_pool_consistency()

            return {
                'status': 'ok',
                'timestamp': datetime.now().isoformat(),
                'inconsistencies': {
                    'missing_from_disk': len(inconsistencies.get('missing_from_disk', [])),
                    'missing_from_state': len(inconsistencies.get('missing_from_state', [])),
                    'ghost_in_use': len(inconsistencies.get('ghost_in_use', [])),
                    'fixed': len(inconsistencies.get('fixed', []))
                },
                'details': inconsistencies
            }

        except Exception as e:
            logger.error(f"Consistency verification failed: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def get_instance_info(self, repo_name: str) -> Dict:
        """获取特定仓库的实例信息"""
        try:
            with self.repo_manager.pool_lock:
                if repo_name not in self.repo_manager.pool_state:
                    return {'status': 'error', 'error': f'Repository {repo_name} not found'}

                state = self.repo_manager.pool_state[repo_name]
                current_time = time.time()

                instances = {
                    'available': [],
                    'in_use': []
                }

                # 可用实例
                for iid in state['available']:
                    pool_path = os.path.join(
                        self.repo_manager.POOL_BASE_DIR,
                        f"{repo_name}-{iid}"
                    )
                    instances['available'].append({
                        'instance_id': iid,
                        'path': pool_path,
                        'exists': os.path.exists(pool_path)
                    })

                # 使用中的实例
                for iid, info in state['in_use'].items():
                    acquired_at = info.get('acquired_at', 0)
                    held_duration = current_time - acquired_at if acquired_at else 0

                    workspace_path = os.path.join(
                        self.repo_manager.REPO_BASE_DIR,
                        str(info.get('task_id', 'unknown')),
                        repo_name
                    )

                    instances['in_use'].append({
                        'instance_id': iid,
                        'task_id': info.get('task_id'),
                        'held_hours': round(held_duration / 3600, 2),
                        'path': workspace_path,
                        'exists': os.path.exists(workspace_path),
                        'is_ghost': not os.path.exists(workspace_path)
                    })

                return {
                    'status': 'ok',
                    'timestamp': datetime.now().isoformat(),
                    'repository': repo_name,
                    'total': state['total'],
                    'next_id': state.get('next_id', 0),
                    'instances': instances
                }

        except Exception as e:
            logger.error(f"Failed to get instance info: {str(e)}")
            return {'status': 'error', 'error': str(e)}


# Flask 应用
app = Flask(__name__)
CORS(app)  # 允许跨域访问
monitor_service = PoolMonitorService()


@app.route('/api/pool/status', methods=['GET'])
def get_status():
    """获取池状态"""
    return jsonify(monitor_service.get_pool_status())


@app.route('/api/pool/cleanup', methods=['POST'])
def trigger_cleanup():
    """触发清理"""
    data = request.get_json() or {}
    dry_run = data.get('dry_run', True)
    max_hours = data.get('max_hours', None)

    result = monitor_service.check_and_cleanup(
        dry_run=dry_run,
        max_hours=max_hours,
        auto_cleanup=True
    )
    return jsonify(result)


@app.route('/api/pool/stats', methods=['GET'])
def get_stats():
    """获取统计信息"""
    return jsonify(monitor_service.stats)


@app.route('/api/pool/verify', methods=['POST'])
def verify_consistency():
    """验证一致性"""
    result = monitor_service.verify_consistency()
    return jsonify(result)


@app.route('/api/pool/instances/<repo_name>', methods=['GET'])
def get_instances(repo_name):
    """获取特定仓库的实例信息"""
    result = monitor_service.get_instance_info(repo_name)
    return jsonify(result)


@app.route('/api/pool/monitor/start', methods=['POST'])
def start_monitor():
    """启动监控"""
    result = monitor_service.start_monitor()
    return jsonify(result)


@app.route('/api/pool/monitor/stop', methods=['POST'])
def stop_monitor():
    """停止监控"""
    result = monitor_service.stop_monitor()
    return jsonify(result)


@app.route('/health', methods=['GET'])
def health_check():
    """健康检查"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'monitor_running': monitor_service.running
    })


def main():
    """主函数"""
    import argparse

    parser = argparse.ArgumentParser(description='Pool Monitor API Service')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind')
    parser.add_argument('--port', type=int, default=5001, help='Port to bind')
    parser.add_argument('--auto-start', action='store_true', help='Auto start monitor')
    parser.add_argument('--debug', action='store_true', help='Debug mode')

    args = parser.parse_args()

    # 自动启动监控
    if args.auto_start:
        monitor_service.start_monitor()
        logger.info("Monitor auto-started")

    # 启动 Flask 服务
    logger.info(f"Starting Pool Monitor API Service on {args.host}:{args.port}")
    app.run(host=args.host, port=args.port, debug=args.debug)


if __name__ == '__main__':
    main()