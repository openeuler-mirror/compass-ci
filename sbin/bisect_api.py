#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Bisect API 客户端 - 支持错误和性能 bisect 任务
"""

import os
import sys
import json
import argparse
import urllib.parse
from typing import Optional, Dict, Any

try:
    import requests
except ImportError:
    print("错误: 需要安装 requests 库")
    print("请运行: pip3 install requests")
    sys.exit(1)


class BisectAPIClient:
    """Bisect API 客户端"""

    def __init__(self, host: Optional[str] = None):
        self.host = host or os.environ.get('BISECT_API_HOST', 'localhost:9999')
        self.base_url = f"http://{self.host}/api/v1"
        self.session = requests.Session()
        self.session.headers.update({'Content-Type': 'application/json'})

        # 颜色定义
        self.RED = '\033[0;31m'
        self.GREEN = '\033[0;32m'
        self.YELLOW = '\033[1;33m'
        self.BLUE = '\033[0;34m'
        self.NC = '\033[0m'  # No Color

    def _print_colored(self, color: str, message: str):
        """打印带颜色的消息"""
        print(f"{color}{message}{self.NC}")

    def _make_request(self, method: str, endpoint: str,
                      params: Optional[Dict] = None,
                      json_data: Optional[Dict] = None) -> Optional[Dict]:
        """发送 HTTP 请求"""
        url = f"{self.base_url}{endpoint}"

        # 显示请求信息
        self._print_colored(self.BLUE, f"请求: {method} {url}")
        if params:
            # URL 编码自动处理
            query_string = urllib.parse.urlencode(params)
            self._print_colored(self.BLUE, f"参数: {query_string}")
        if json_data:
            self._print_colored(self.BLUE, f"数据: {json.dumps(json_data, ensure_ascii=False)}")

        try:
            response = self.session.request(
                method=method,
                url=url,
                params=params,  # requests 会自动进行 URL 编码
                json=json_data,
                timeout=30
            )

            self._print_colored(self.BLUE, f"状态码: {response.status_code}")

            if response.status_code >= 200 and response.status_code < 300:
                self._print_colored(self.GREEN, "响应成功:")
                if response.content:
                    data = response.json()

                    # 特殊处理：如果是任务列表，将 id 字段放在最前面
                    if isinstance(data, dict) and 'tasks' in data and isinstance(data['tasks'], list):
                        reordered_tasks = []
                        for task in data['tasks']:
                            if isinstance(task, dict) and 'id' in task:
                                # 创建新字典，id 放在最前面
                                ordered_task = {'id': task['id']}
                                # 添加其他字段（保持原顺序）
                                for key, value in task.items():
                                    if key != 'id':
                                        ordered_task[key] = value
                                reordered_tasks.append(ordered_task)
                            else:
                                reordered_tasks.append(task)
                        data['tasks'] = reordered_tasks

                    print(json.dumps(data, indent=2, ensure_ascii=False))
                    return data
                else:
                    print("(空响应)")
                    return {}
            else:
                self._print_colored(self.RED, "响应失败:")
                try:
                    error_data = response.json()
                    print(json.dumps(error_data, indent=2, ensure_ascii=False))
                except:
                    print(response.text)
                return None

        except requests.exceptions.ConnectionError:
            self._print_colored(self.RED, f"错误: 无法连接到服务器 {self.base_url}")
            self._print_colored(self.RED, "请检查服务是否正在运行")
        except requests.exceptions.Timeout:
            self._print_colored(self.RED, "错误: 请求超时")
        except Exception as e:
            self._print_colored(self.RED, f"错误: {str(e)}")

        return None

    def new_task(self, task_data: Dict[str, Any]) -> Optional[Dict]:
        """创建新的 bisect 任务"""
        return self._make_request("POST", "/new_bisect_task", json_data=task_data)

    def list_tasks(self, status: Optional[str] = None,
                   error_id: Optional[str] = None,
                   bad_job_id: Optional[str] = None,
                   category: Optional[str] = None,
                   hours: Optional[int] = None,
                   git_url: Optional[str] = None,
                   task_id: Optional[str] = None,
                   task_ids: Optional[str] = None,
                   commit: Optional[str] = None,
                   limit: Optional[int] = None) -> Optional[Dict]:
        """
        获取任务列表

        参数:
            status: 任务状态筛选
            error_id: 错误ID筛选（自动URL编码）
            bad_job_id: bad_job_id筛选
            category: 任务类型筛选 (build/boot)
            hours: 最近N小时内的任务
            git_url: Git仓库URL筛选
            task_id: 单个任务ID筛选
            task_ids: 多个任务ID筛选（逗号分隔）
            commit: first_bad_commit 筛选（支持完整或短SHA）
            limit: 返回数量限制
        """
        params = {}
        if status:
            params['status'] = status
        if error_id:
            params['error_id'] = error_id  # requests 会自动 URL 编码
        if bad_job_id:
            params['bad_job_id'] = bad_job_id
        if category:
            params['category'] = category
        if hours:
            params['hours'] = str(hours)
        if git_url:
            params['git_url'] = git_url
        if task_id:
            params['task_id'] = task_id
        if task_ids:
            params['task_ids'] = task_ids
        if commit:
            params['first_bad_commit'] = commit  # 映射 commit 到 first_bad_commit
        if limit:
            params['limit'] = str(limit)

        return self._make_request("GET", "/list_bisect_tasks", params=params)

    def delete_tasks(self, **conditions) -> Optional[Dict]:
        """根据条件删除任务"""
        if not conditions:
            self._print_colored(self.RED, "错误: 请提供删除条件")
            return None

        # 确认删除
        self._print_colored(self.YELLOW, f"警告: 将删除符合条件的任务: {conditions}")
        confirm = input("是否继续? (y/N): ")
        if confirm.lower() != 'y':
            print("操作已取消")
            return None

        return self._make_request("DELETE", "/delete_tasks", params=conditions)

    def reset_failed_tasks(self) -> Optional[Dict]:
        """重置失败的任务"""
        self._print_colored(self.YELLOW, "警告: 将重置所有失败的任务")
        confirm = input("是否继续? (y/N): ")
        if confirm.lower() != 'y':
            print("操作已取消")
            return None

        return self._make_request("DELETE", "/reset_failed_tasks")

    def reset_processing_tasks(self) -> Optional[Dict]:
        """重置 processing 状态的任务为 wait"""
        self._print_colored(self.YELLOW, "警告: 将重置所有 processing 状态的任务为 wait")
        confirm = input("是否继续? (y/N): ")
        if confirm.lower() != 'y':
            print("操作已取消")
            return None

        return self._make_request("POST", "/reset_processing_tasks")

    def reset_verifying_tasks(self) -> Optional[Dict]:
        """重置 verifying 状态的任务为 wait"""
        self._print_colored(self.YELLOW, "警告: 将重置所有 verifying 状态的任务为 wait")
        confirm = input("是否继续? (y/N): ")
        if confirm.lower() != 'y':
            print("操作已取消")
            return None

        return self._make_request("POST", "/reset_verifying_tasks")

    def reset_pending_verification_tasks(self) -> Optional[Dict]:
        """重置 pending_verification 状态的任务为 wait"""
        self._print_colored(self.YELLOW, "警告: 将重置所有 pending_verification 状态的任务为 wait")
        confirm = input("是否继续? (y/N): ")
        if confirm.lower() != 'y':
            print("操作已取消")
            return None

        return self._make_request("POST", "/reset_pending_verification_tasks")

    def cleanup_orphaned_verifying(self) -> Optional[Dict]:
        """清理孤立的 verifying 任务（关联任务已失败或不存在）"""
        self._print_colored(self.YELLOW, "警告: 将清理所有孤立的 verifying 任务（关联任务已失败或不存在）")
        confirm = input("是否继续? (y/N): ")
        if confirm.lower() != 'y':
            print("操作已取消")
            return None

        return self._make_request("POST", "/cleanup_orphaned_verifying")

    def set_tasks_to_verifying(self, task_ids: list) -> Optional[Dict]:
        """手动设置一个或多个任务的状态为 verifying"""
        self._print_colored(self.YELLOW, f"警告: 将设置 {len(task_ids)} 个任务的状态为 'verifying'")
        self._print_colored(self.YELLOW, f"任务 IDs: {task_ids}")
        confirm = input("是否继续? (y/N): ")
        if confirm.lower() != 'y':
            print("操作已取消")
            return None
        
        json_data = {"task_ids": task_ids}
        return self._make_request("POST", "/set_tasks_to_verifying", json_data=json_data)

    def reset_task(self, task_id: str) -> Optional[Dict]:
        """重置指定ID的任务为wait状态（已废弃，请使用reset_tasks）"""
        if not task_id.isdigit():
            self._print_colored(self.RED, "错误: 任务ID必须是数字")
            return None

        return self._make_request("POST", f"/reset_task?id={task_id}")

    def reset_tasks(self, **conditions) -> Optional[Dict]:
        """根据条件重置任务为wait状态"""
        if not conditions:
            self._print_colored(self.RED, "错误: 请提供重置条件")
            return None

        # 确认重置
        self._print_colored(self.YELLOW, f"警告: 将重置符合条件的任务: {conditions}")
        confirm = input("是否继续? (y/N): ")
        if confirm.lower() != 'y':
            print("操作已取消")
            return None

        return self._make_request("POST", "/reset_tasks", params=conditions)

    def thread_pool_status(self) -> Optional[Dict]:
        """获取线程池状态"""
        return self._make_request("GET", "/thread_pool_status")

    def toggle_producer(self, enable: bool) -> Optional[Dict]:
        """启用或禁用生产者"""
        state = "enable" if enable else "disable"
        return self._make_request("POST", f"/toggle_producer?state={state}")

    def producer_status(self) -> Optional[Dict]:
        """获取生产者状态"""
        return self._make_request("GET", "/producer_status")

    def trigger_producer_run(self, force: bool = False) -> Optional[Dict]:
        """手动触发生产者运行"""
        params = {'force': 'true'} if force else {}
        return self._make_request("POST", "/trigger_producer_run", params=params)

    # Pool monitoring methods
    def pool_status(self) -> Optional[Dict]:
        """获取仓库池状态"""
        return self._make_request("GET", "/pool/status")

    def pool_cleanup(self, dry_run: bool = True, max_age_days: Optional[float] = None) -> Optional[Dict]:
        """Trigger workspace cleanup"""
        data = {"dry_run": dry_run}
        if max_age_days is not None:
            data["max_age_days"] = max_age_days
        return self._make_request("POST", "/pool/cleanup", json_data=data)

    def pool_stats(self) -> Optional[Dict]:
        """Get monitor statistics"""
        return self._make_request("GET", "/pool/stats")

    def pool_verify(self) -> Optional[Dict]:
        """Verify workspace consistency"""
        return self._make_request("POST", "/pool/verify")

    def pool_monitor_start(self) -> Optional[Dict]:
        """启动池监控线程"""
        return self._make_request("POST", "/pool/monitor/start")

    def pool_monitor_stop(self) -> Optional[Dict]:
        """停止池监控线程"""
        return self._make_request("POST", "/pool/monitor/stop")


def add_common_filter_args(parser, include_limit=False):
    """
    为 parser 添加通用的筛选参数

    Args:
        parser: ArgumentParser 或 subparser 对象
        include_limit: 是否包含 limit 参数（仅 list_tasks 需要）
    """
    parser.add_argument('--id', help='任务ID')
    parser.add_argument('--error_id', help='错误ID')
    parser.add_argument('--bad_job_id', help='Bad job ID')
    parser.add_argument('--git_url', help='Git URL')
    parser.add_argument('--category', help='任务类型 (build/function/performance)')
    parser.add_argument('--status', help='任务状态 (wait/processing/success/failed/verifying)')
    parser.add_argument('--commit', help='按first_bad_commit筛选（支持完整或短SHA）')

    if include_limit:
        parser.add_argument('--limit', type=int, help='限制返回数量 (默认: 100000)')


def build_filter_conditions(args):
    """
    从 args 构建筛选条件字典

    Args:
        args: argparse 解析后的参数对象

    Returns:
        条件字典
    """
    conditions = {}
    if hasattr(args, 'id') and args.id:
        conditions['task_id'] = args.id  # 映射 id 到 task_id
    if hasattr(args, 'error_id') and args.error_id:
        conditions['error_id'] = args.error_id
    if hasattr(args, 'bad_job_id') and args.bad_job_id:
        conditions['bad_job_id'] = args.bad_job_id
    if hasattr(args, 'git_url') and args.git_url:
        conditions['git_url'] = args.git_url
    if hasattr(args, 'category') and args.category:
        conditions['category'] = args.category
    if hasattr(args, 'status') and args.status:
        conditions['status'] = args.status
    if hasattr(args, 'commit') and args.commit:
        conditions['first_bad_commit'] = args.commit  # 映射 commit 到 first_bad_commit
    return conditions


def main():
    """主函数"""
    parser = argparse.ArgumentParser(
        description='Bisect API 客户端 - 支持错误和性能 bisect 任务',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例用法:
  # 创建新任务
  %(prog)s new_task --bad_job_id 123456 --error_id "compile_error"
  %(prog)s new_task --bad_job_id 123456 --metric "hackbench.throughput"
  %(prog)s new_task -f task.json
  %(prog)s new_task -j '{"bad_job_id":"123456","error_id":"test.error"}'

  # 查询任务列表（支持组合筛选）
  %(prog)s list_tasks
  %(prog)s list_tasks --status success
  %(prog)s list_tasks --error_id "stderr.eid.fs/#p/vfs_file.c:warning"
  %(prog)s list_tasks --bad_job_id 12345 --limit 10
  %(prog)s list_tasks --status failed --category build
  %(prog)s list_tasks --category boot --hours 24
  %(prog)s list_tasks --git_url "https://github.com/torvalds/linux.git"
  %(prog)s list_tasks --task_ids 12345,67890
  %(prog)s list_tasks --commit bbaaa756ad25
  %(prog)s list_tasks --commit bbaaa756ad25c0e792fcd195d32acd5715f76b12

  # 删除任务（支持组合筛选）
  %(prog)s delete_tasks --id 1001
  %(prog)s delete_tasks --error_id "test.error"
  %(prog)s delete_tasks --commit bbaaa756ad25
  %(prog)s delete_tasks --status failed --category build

  # 重置任务（支持组合筛选）
  %(prog)s reset_failed
  %(prog)s reset_processing
  %(prog)s reset_verifying
  %(prog)s reset_pending_verification
  %(prog)s cleanup_orphaned_verifying
  %(prog)s reset_tasks --id 12345
  %(prog)s reset_tasks --commit bbaaa756ad25
  %(prog)s reset_tasks --status failed --category build
  %(prog)s set_verifying --ids 12345 67890

  # 生产者控制
  %(prog)s enable_producer
  %(prog)s disable_producer
  %(prog)s producer_status
  %(prog)s trigger_producer

  # 查看线程池状态
  %(prog)s thread_status

  # 池监控命令
  %(prog)s pool_status
  %(prog)s pool_cleanup --dry-run
  %(prog)s pool_cleanup --max-hours 12
  %(prog)s pool_stats
  %(prog)s pool_verify
  %(prog)s pool_instances ltp
  %(prog)s pool_monitor_start
  %(prog)s pool_monitor_stop

环境变量:
  BISECT_API_HOST - API服务器地址 (默认: localhost:9999)

注意:
  • 支持特殊字符（#、&、空格等）的自动URL编码
  • error_id 和 metric 参数互斥，只能指定其中一个
  • list_tasks 支持组合多种筛选条件（status, category, hours等）
  • 使用 -h 查看每个命令的详细参数
"""
    )

    subparsers = parser.add_subparsers(dest='command', help='可用命令')

    # new_task 命令
    new_task_parser = subparsers.add_parser(
        'new_task',
        help='创建新的bisect任务',
        description='创建新的bisect任务，支持错误类型和性能类型任务',
        epilog="""
示例:
  # 错误类型任务
  %(prog)s --bad_job_id 123456 --error_id "compile_error"
  %(prog)s --bad_job_id 123456 --error_id "stderr.eid.fs/#p/vfs_file.c:warning"

  # 性能类型任务
  %(prog)s --bad_job_id 123456 --metric "hackbench.throughput"
  %(prog)s --bad_job_id 123456 --metric "boot.time" --git_url "https://github.com/torvalds/linux.git"

  # 从JSON文件读取
  %(prog)s -f task.json

  # 直接传入JSON字符串
  %(prog)s -j '{"bad_job_id":"123456","error_id":"test.error"}'
"""
    )
    new_task_group = new_task_parser.add_mutually_exclusive_group(required=False)
    new_task_group.add_argument('-f', '--file', help='从JSON文件读取任务数据')
    new_task_group.add_argument('-j', '--json', help='直接传入JSON字符串')
    new_task_parser.add_argument('--bad_job_id', help='Bad job ID (必需，除非使用-f或-j)')
    new_task_parser.add_argument('--error_id', help='错误ID (创建错误类型任务)')
    new_task_parser.add_argument('--metric', help='性能指标名称 (创建性能类型任务)')
    new_task_parser.add_argument('--git_url', help='Git仓库URL (可选)')
    new_task_parser.add_argument('--good_commit', help='已知的好提交SHA (可选)')

    # list_tasks 命令
    list_parser = subparsers.add_parser(
        'list_tasks',
        help='查询任务列表',
        description='查询bisect任务列表，支持多种筛选条件',
        epilog="""
示例:
  # 查询所有任务
  %(prog)s

  # 按状态筛选
  %(prog)s --status success
  %(prog)s --status failed

  # 按error_id筛选（支持特殊字符）
  %(prog)s --error_id "stderr.eid.fs/#p/vfs_file.c:warning"
  %(prog)s --error_id "makepkg.eid.fs/#p/vfs_file.c:warning:Excess-function-parameter"

  # 按任务类型筛选
  %(prog)s --category build
  %(prog)s --category boot

  # 按时间筛选
  %(prog)s --hours 24
  %(prog)s --hours 48 --status failed

  # 按Git仓库筛选
  %(prog)s --git_url "https://github.com/torvalds/linux.git"

  # 按任务ID筛选
  %(prog)s --task_id 12345
  %(prog)s --task_ids 12345,67890,99999

  # 组合筛选示例
  %(prog)s --status wait --error_id "test.error" --limit 10
  %(prog)s --bad_job_id 12345 --status success
  %(prog)s --status failed --category build
  %(prog)s --category boot --hours 24 --status failed
  %(prog)s --git_url "https://github.com/torvalds/linux.git" --status success

注意: error_id中的特殊字符（如 #、&、空格）会自动进行URL编码
"""
    )
    # list_tasks 使用通用筛选参数（包含 limit）
    # 但需要额外添加 task_id, task_ids, hours 参数
    list_parser.add_argument('--task_id', help='按单个任务ID筛选')
    list_parser.add_argument('--task_ids', help='按多个任务ID筛选（逗号分隔，如: 12345,67890）')
    list_parser.add_argument('--hours', type=int, help='筛选最近N小时内的任务')
    add_common_filter_args(list_parser, include_limit=True)

    # delete_tasks 命令
    delete_parser = subparsers.add_parser(
        'delete_tasks',
        help='删除符合条件的任务',
        description='根据指定条件删除bisect任务',
        epilog="""
示例:
  # 按ID删除
  %(prog)s --id 1001

  # 按error_id删除
  %(prog)s --error_id "test.error"

  # 按bad_job_id删除
  %(prog)s --bad_job_id 12345

  # 按commit删除
  %(prog)s --commit bbaaa756ad25
  %(prog)s --commit bbaaa756ad25c0e792fcd195d32acd5715f76b12

  # 按状态和类型组合删除
  %(prog)s --status failed --category build
  %(prog)s --status wait --category boot

  # 组合条件删除（AND关系）
  %(prog)s --error_id "test.error" --bad_job_id 12345
  %(prog)s --git_url "https://github.com/torvalds/linux.git" --status failed
  %(prog)s --commit bbaaa756ad25 --status failed

警告: 删除操作不可恢复，请谨慎使用
"""
    )
    # delete_tasks 使用通用筛选参数
    add_common_filter_args(delete_parser)

    # 其他命令
    subparsers.add_parser('reset_failed', help='重置所有失败状态的任务为wait状态')
    subparsers.add_parser('reset_processing', help='重置所有processing状态的任务为wait状态')
    subparsers.add_parser('reset_verifying', help='重置所有verifying状态的任务为wait状态')
    subparsers.add_parser('reset_pending_verification', help='重置所有pending_verification状态的任务为wait状态')
    subparsers.add_parser('cleanup_orphaned_verifying', help='清理孤立的verifying任务（关联任务已失败或不存在）')

    set_verifying_parser = subparsers.add_parser(
        'set_verifying',
        help='手动设置一个或多个任务的状态为 verifying',
        description='手动设置一个或多个任务的状态为 verifying，以便验证消费者可以处理它们。',
        epilog="""
示例:
  # 设置单个任务
  %(prog)s --ids 12345

  # 设置多个任务
  %(prog)s --ids 12345 67890
"""
    )
    set_verifying_parser.add_argument('--ids', required=True, nargs='+', help='要设置为 verifying 状态的任务ID列表')

    # reset_tasks 命令（改为复数，统一命名）
    reset_tasks_parser = subparsers.add_parser(
        'reset_tasks',
        help='根据条件重置任务为wait状态',
        description='根据指定条件重置bisect任务为wait状态（仅限failed或processing状态）',
        epilog="""
示例:
  # 按任务ID重置
  %(prog)s --id 12345

  # 按error_id重置
  %(prog)s --error_id "test.error"

  # 按commit重置
  %(prog)s --commit bbaaa756ad25

  # 按状态重置
  %(prog)s --status failed

  # 组合条件重置
  %(prog)s --status failed --category build
  %(prog)s --git_url "https://github.com/torvalds/linux.git" --status processing

注意: 只能重置 failed 或 processing 状态的任务
"""
    )
    # reset_tasks 使用通用筛选参数
    add_common_filter_args(reset_tasks_parser)

    subparsers.add_parser('thread_status', help='获取线程池状态信息')
    subparsers.add_parser('enable_producer', help='启用后台生产者任务')
    subparsers.add_parser('disable_producer', help='禁用后台生产者任务')
    subparsers.add_parser('producer_status', help='获取生产者运行状态')
    trigger_parser = subparsers.add_parser('trigger_producer', help='手动触发一次生产者运行')
    trigger_parser.add_argument('--force', action='store_true', help='强制运行（即使今天已运行过）')

    # Pool monitoring commands
    subparsers.add_parser('pool_status', help='获取仓库池状态')

    pool_cleanup_parser = subparsers.add_parser('pool_cleanup', help='Trigger workspace cleanup')
    pool_cleanup_parser.add_argument('--dry-run', action='store_true', default=True, help='Preview mode')
    pool_cleanup_parser.add_argument('--execute', action='store_true', help='Execute cleanup')
    pool_cleanup_parser.add_argument('--max-age-days', type=float, help='Max workspace age in days (default: 7)')

    subparsers.add_parser('pool_stats', help='Get monitor statistics')
    subparsers.add_parser('pool_verify', help='Verify workspace consistency')

    subparsers.add_parser('pool_monitor_start', help='Start monitor thread')
    subparsers.add_parser('pool_monitor_stop', help='Stop monitor thread')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    # 创建客户端
    client = BisectAPIClient()

    # 执行命令
    if args.command == 'new_task':
        if args.file:
            with open(args.file, 'r') as f:
                task_data = json.load(f)
        elif args.json:
            task_data = json.loads(args.json)
        else:
            # 从参数构建任务
            task_data = {'bad_job_id': args.bad_job_id}

            if args.error_id and args.metric:
                print("错误: --error_id 和 --metric 不能同时指定")
                return
            elif args.error_id:
                task_data['error_id'] = args.error_id
            elif args.metric:
                task_data['bisect_metric'] = args.metric
            else:
                print("错误: 必须指定 --error_id 或 --metric")
                return

            if args.git_url:
                task_data['git_url'] = args.git_url
            if args.good_commit:
                task_data['good_commit'] = args.good_commit

        client.new_task(task_data)

    elif args.command == 'list_tasks':
        client.list_tasks(
            status=args.status,
            error_id=args.error_id,
            bad_job_id=args.bad_job_id,
            category=args.category,
            hours=args.hours,
            git_url=args.git_url,
            task_id=args.task_id,
            task_ids=args.task_ids,
            commit=args.commit,
            limit=args.limit
        )

    elif args.command == 'delete_tasks':
        conditions = build_filter_conditions(args)
        client.delete_tasks(**conditions)

    elif args.command == 'reset_failed':
        client.reset_failed_tasks()
    elif args.command == 'reset_processing':
        client.reset_processing_tasks()
    elif args.command == 'reset_verifying':
        client.reset_verifying_tasks()
    elif args.command == 'reset_pending_verification':
        client.reset_pending_verification_tasks()
    elif args.command == 'cleanup_orphaned_verifying':
        client.cleanup_orphaned_verifying()
    elif args.command == 'set_verifying':
        client.set_tasks_to_verifying(args.ids)
    elif args.command == 'reset_task':
        # 兼容旧命令
        client.reset_task(args.id)
    elif args.command == 'reset_tasks':
        # 新的复数命令，使用通用筛选条件
        conditions = build_filter_conditions(args)
        client.reset_tasks(**conditions)
    elif args.command == 'thread_status':
        client.thread_pool_status()
    elif args.command == 'enable_producer':
        client.toggle_producer(True)
    elif args.command == 'disable_producer':
        client.toggle_producer(False)
    elif args.command == 'producer_status':
        client.producer_status()
    elif args.command == 'trigger_producer':
        client.trigger_producer_run(force=args.force)

    # Pool monitoring commands
    elif args.command == 'pool_status':
        client.pool_status()
    elif args.command == 'pool_cleanup':
        dry_run = not args.execute
        client.pool_cleanup(dry_run=dry_run, max_age_days=getattr(args, 'max_age_days', None))
    elif args.command == 'pool_stats':
        client.pool_stats()
    elif args.command == 'pool_verify':
        client.pool_verify()
    elif args.command == 'pool_monitor_start':
        client.pool_monitor_start()
    elif args.command == 'pool_monitor_stop':
        client.pool_monitor_stop()


if __name__ == '__main__':
    main()