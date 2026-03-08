#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Workspace Monitor API Service

Provides REST API endpoints to monitor and manage bisect workspaces:
- GET /api/pool/status - Get workspace status
- POST /api/pool/cleanup - Trigger cleanup of old workspaces
- GET /api/pool/stats - Get statistics
- POST /api/pool/verify - Verify workspace consistency
"""

import os
import sys
import time
import threading
from datetime import datetime
from typing import Dict, Optional
from flask import Flask, jsonify, request
from flask_cors import CORS
import schedule

sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lib'))
from log_config import logger
from repo_manager import SharedRepoManager


class PoolMonitorService:
    """Workspace monitor service (simplified architecture)"""

    CHECK_INTERVAL_MINUTES = 10
    MAX_WORKSPACE_AGE_DAYS = 7

    def __init__(self):
        self.repo_manager = SharedRepoManager()
        self.stats = {
            'service_start_time': time.time(),
            'last_check_time': 0,
            'total_checks': 0,
            'total_cleaned': 0,
            'last_cleanup_time': 0,
            'last_cleanup_count': 0
        }
        self.monitor_thread = None
        self.running = False

    def start_monitor(self):
        """Start background monitor thread"""
        if self.running:
            return {"status": "already running"}

        self.running = True
        self.monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self.monitor_thread.start()
        logger.info("Workspace monitor thread started")
        return {"status": "started"}

    def stop_monitor(self):
        """Stop background monitor"""
        self.running = False
        if self.monitor_thread:
            self.monitor_thread.join(timeout=5)
        logger.info("Workspace monitor thread stopped")
        return {"status": "stopped"}

    def _monitor_loop(self):
        """Monitor loop"""
        schedule.every(self.CHECK_INTERVAL_MINUTES).minutes.do(self._periodic_check)

        while self.running:
            schedule.run_pending()
            time.sleep(60)

    def _periodic_check(self):
        """Periodic check"""
        try:
            logger.info("Starting periodic workspace check...")
            result = self.check_and_cleanup(dry_run=False)
            self.stats['last_check_time'] = time.time()
            self.stats['total_checks'] += 1
            logger.info(f"Periodic check completed: {result.get('summary', {})}")
        except Exception as e:
            logger.error(f"Periodic check failed: {str(e)}")

    def get_pool_status(self) -> Dict:
        """Get workspace status"""
        try:
            pool_stats = self.repo_manager.get_pool_stats()

            # List active workspaces
            workspaces = []
            workspace_dir = self.repo_manager.REPO_BASE_DIR
            if os.path.exists(workspace_dir):
                for task_id in os.listdir(workspace_dir):
                    task_path = os.path.join(workspace_dir, task_id)
                    if not os.path.isdir(task_path):
                        continue
                    try:
                        mtime = os.path.getmtime(task_path)
                        age_hours = (time.time() - mtime) / 3600
                        repos = [d for d in os.listdir(task_path)
                                 if os.path.isdir(os.path.join(task_path, d))]
                        workspaces.append({
                            'task_id': task_id,
                            'repos': repos,
                            'age_hours': round(age_hours, 2),
                        })
                    except OSError:
                        continue

            # List pristine repos
            pristine_repos = []
            pristine_dir = self.repo_manager.PRISTINE_BASE_DIR
            if os.path.exists(pristine_dir):
                for name in os.listdir(pristine_dir):
                    path = os.path.join(pristine_dir, name)
                    if os.path.isdir(path):
                        pristine_repos.append(name)

            return {
                'status': 'ok',
                'timestamp': datetime.now().isoformat(),
                'architecture': 'simplified',
                'summary': {
                    'active_workspaces': len(workspaces),
                    'pristine_repos': len(pristine_repos),
                    'max_concurrent_clones': pool_stats.get('max_concurrent_clones', 0),
                },
                'workspaces': sorted(workspaces, key=lambda x: x['age_hours'], reverse=True),
                'pristine_repos': pristine_repos,
                'service_stats': self.stats
            }

        except Exception as e:
            logger.error(f"Failed to get workspace status: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def check_and_cleanup(self, dry_run: bool = True,
                         max_age_days: Optional[float] = None) -> Dict:
        """Check and cleanup old workspaces"""
        age_days = max_age_days if max_age_days is not None else self.MAX_WORKSPACE_AGE_DAYS

        try:
            if dry_run:
                # Just report what would be cleaned
                candidates = []
                workspace_dir = self.repo_manager.REPO_BASE_DIR
                if os.path.exists(workspace_dir):
                    max_age_seconds = age_days * 86400
                    for task_id in os.listdir(workspace_dir):
                        task_path = os.path.join(workspace_dir, task_id)
                        if not os.path.isdir(task_path):
                            continue
                        try:
                            age_seconds = time.time() - os.path.getmtime(task_path)
                            if age_seconds > max_age_seconds:
                                candidates.append({
                                    'task_id': task_id,
                                    'age_hours': round(age_seconds / 3600, 2),
                                    'action': 'would_clean'
                                })
                        except OSError:
                            continue

                return {
                    'status': 'ok',
                    'timestamp': datetime.now().isoformat(),
                    'dry_run': True,
                    'summary': {'candidates': len(candidates)},
                    'candidates': candidates[:20]
                }
            else:
                deleted, skipped = self.repo_manager.cleanup_old_workspaces(max_age_days=age_days)
                self.stats['total_cleaned'] += deleted
                self.stats['last_cleanup_time'] = time.time()
                self.stats['last_cleanup_count'] = deleted

                return {
                    'status': 'ok',
                    'timestamp': datetime.now().isoformat(),
                    'dry_run': False,
                    'summary': {'deleted': deleted, 'skipped': skipped}
                }

        except Exception as e:
            logger.error(f"Check and cleanup failed: {str(e)}")
            return {'status': 'error', 'error': str(e)}

    def verify_consistency(self) -> Dict:
        """Verify workspace consistency"""
        try:
            issues = []
            workspace_dir = self.repo_manager.REPO_BASE_DIR
            pristine_dir = self.repo_manager.PRISTINE_BASE_DIR

            # Check pristine repos are valid git repos
            if os.path.exists(pristine_dir):
                for name in os.listdir(pristine_dir):
                    path = os.path.join(pristine_dir, name)
                    if os.path.isdir(path) and not self.repo_manager._is_git_repo(path):
                        issues.append({
                            'type': 'invalid_pristine',
                            'repo': name,
                            'path': path
                        })

            # Check for empty workspace dirs (cleanup residue)
            if os.path.exists(workspace_dir):
                for task_id in os.listdir(workspace_dir):
                    task_path = os.path.join(workspace_dir, task_id)
                    if os.path.isdir(task_path):
                        contents = os.listdir(task_path)
                        if not contents:
                            issues.append({
                                'type': 'empty_workspace',
                                'task_id': task_id,
                                'path': task_path
                            })

            return {
                'status': 'ok',
                'timestamp': datetime.now().isoformat(),
                'issues_count': len(issues),
                'issues': issues
            }

        except Exception as e:
            logger.error(f"Consistency verification failed: {str(e)}")
            return {'status': 'error', 'error': str(e)}


# Flask app
app = Flask(__name__)
CORS(app)
monitor_service = PoolMonitorService()


@app.route('/api/pool/status', methods=['GET'])
def get_status():
    return jsonify(monitor_service.get_pool_status())


@app.route('/api/pool/cleanup', methods=['POST'])
def trigger_cleanup():
    data = request.get_json() or {}
    dry_run = data.get('dry_run', True)
    max_age_days = data.get('max_age_days', None)

    result = monitor_service.check_and_cleanup(
        dry_run=dry_run,
        max_age_days=max_age_days
    )
    return jsonify(result)


@app.route('/api/pool/stats', methods=['GET'])
def get_stats():
    return jsonify(monitor_service.stats)


@app.route('/api/pool/verify', methods=['POST'])
def verify_consistency():
    result = monitor_service.verify_consistency()
    return jsonify(result)


@app.route('/api/pool/monitor/start', methods=['POST'])
def start_monitor():
    result = monitor_service.start_monitor()
    return jsonify(result)


@app.route('/api/pool/monitor/stop', methods=['POST'])
def stop_monitor():
    result = monitor_service.stop_monitor()
    return jsonify(result)


@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'monitor_running': monitor_service.running
    })


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Workspace Monitor API Service')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind')
    parser.add_argument('--port', type=int, default=5001, help='Port to bind')
    parser.add_argument('--auto-start', action='store_true', help='Auto start monitor')
    parser.add_argument('--debug', action='store_true', help='Debug mode')

    args = parser.parse_args()

    if args.auto_start:
        monitor_service.start_monitor()
        logger.info("Monitor auto-started")

    logger.info(f"Starting Workspace Monitor API Service on {args.host}:{args.port}")
    app.run(host=args.host, port=args.port, debug=args.debug)


if __name__ == '__main__':
    main()
