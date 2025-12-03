#!/usr/bin/env python3
"""
模拟通过API提交任务以测试验证机制
使用 new_bisect_tasks.txt 中的任务通过API接口提交，触发相似度检测和验证流程
"""

import os
import sys
import time
import json
import requests
from typing import Dict, List, Tuple
from collections import defaultdict

# Add paths for imports
sys.path.append(os.environ['CCI_SRC'] + '/container/bisect/lib')
from log_config import logger

class APITaskSubmitter:
    def __init__(self, api_base_url: str = None, task_file_path: str = None):
        """初始化API提交器"""
        self.api_base_url = api_base_url or "http://localhost:5000"
        self.task_file_path = task_file_path or "/home/shiptux/git/gitee/compass-ci/new_bisect_tasks.txt"

        # API endpoints
        self.submit_endpoint = f"{self.api_base_url}/bisect/task"

        # Statistics
        self.stats = {
            'total_tasks': 0,
            'submitted': 0,
            'duplicates': 0,
            'pending_verification': 0,
            'created': 0,
            'errors': 0,
            'verification_tasks': []
        }

        logger.info(f"API提交器初始化 | API: {self.api_base_url} | 文件: {self.task_file_path}")

    def load_tasks(self) -> List[Tuple[str, str]]:
        """加载任务列表文件"""
        tasks = []
        try:
            with open(self.task_file_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue

                    parts = line.split(',', 1)
                    if len(parts) == 2:
                        job_id, error_id = parts
                        tasks.append((job_id.strip(), error_id.strip()))

            logger.info(f"加载了 {len(tasks)} 个任务")
            self.stats['total_tasks'] = len(tasks)
            return tasks

        except Exception as e:
            logger.error(f"加载任务文件失败: {str(e)}")
            return []

    def submit_task(self, job_id: str, error_id: str, dry_run: bool = False) -> Dict:
        """提交单个任务到API"""
        task_data = {
            "bad_job_id": job_id,
            "error_id": error_id
        }

        if dry_run:
            # 模拟模式，不实际发送请求
            logger.debug(f"[DRY RUN] 将提交任务: job_id={job_id}, error_id={error_id[:50]}...")
            return {"status": "dry_run", "message": "Dry run mode"}

        try:
            response = requests.post(
                self.submit_endpoint,
                json=task_data,
                headers={"Content-Type": "application/json"},
                timeout=10
            )

            if response.status_code == 200:
                result = response.json()
                return result
            else:
                logger.error(f"API返回错误 | 状态码: {response.status_code} | 响应: {response.text}")
                return {"status": "error", "message": f"HTTP {response.status_code}"}

        except requests.exceptions.RequestException as e:
            logger.error(f"请求失败: {str(e)}")
            return {"status": "error", "message": str(e)}
        except Exception as e:
            logger.error(f"提交任务异常: {str(e)}")
            return {"status": "error", "message": str(e)}

    def run_submission(self, dry_run: bool = False, batch_size: int = 10, delay: float = 0.1):
        """批量提交任务"""
        logger.info("=" * 80)
        logger.info(f"开始批量任务提交 {'[DRY RUN]' if dry_run else ''}")
        logger.info("=" * 80)

        # 1. 加载任务
        tasks = self.load_tasks()
        if not tasks:
            logger.error("没有加载到任何任务")
            return

        # 2. 批量提交
        start_time = time.time()
        batch_count = 0

        for i, (job_id, error_id) in enumerate(tasks, 1):
            # 提交任务
            result = self.submit_task(job_id, error_id, dry_run)

            self.stats['submitted'] += 1

            # 处理响应
            status = result.get('status')
            if status == 'duplicate':
                self.stats['duplicates'] += 1
                logger.debug(f"[{i}/{len(tasks)}] 重复任务: {error_id[:50]}...")
            elif status == 'pending_verification':
                self.stats['pending_verification'] += 1
                logger.info(f"[{i}/{len(tasks)}] 待验证: {error_id[:50]}... | {result.get('message', '')}")
                self.stats['verification_tasks'].append({
                    'job_id': job_id,
                    'error_id': error_id,
                    'message': result.get('message', '')
                })
            elif status == 'created':
                self.stats['created'] += 1
                logger.info(f"[{i}/{len(tasks)}] 创建成功: {error_id[:50]}...")
            else:
                self.stats['errors'] += 1
                logger.warning(f"[{i}/{len(tasks)}] 错误: {error_id[:50]}... | {result.get('message', '')}")

            # 批次控制
            batch_count += 1
            if batch_count >= batch_size:
                # 批次完成，短暂休息
                time.sleep(delay)
                batch_count = 0

                # 进度报告
                elapsed = time.time() - start_time
                rate = i / elapsed
                eta = (len(tasks) - i) / rate if rate > 0 else 0
                logger.info(
                    f"进度: {i}/{len(tasks)} ({i/len(tasks)*100:.1f}%) | "
                    f"速率: {rate:.1f} tasks/s | ETA: {eta:.0f}s"
                )

        elapsed_time = time.time() - start_time

        # 3. 输出结果
        self.print_results(elapsed_time)

        # 4. 保存结果
        self.save_results()

    def print_results(self, elapsed_time: float):
        """打印提交结果"""
        logger.info("=" * 80)
        logger.info("任务提交结果汇总")
        logger.info("=" * 80)

        logger.info(f"总任务数: {self.stats['total_tasks']}")
        logger.info(f"提交任务数: {self.stats['submitted']}")
        logger.info(f"提交时间: {elapsed_time:.2f} 秒")
        logger.info(f"提交速率: {self.stats['submitted']/elapsed_time:.1f} tasks/s")

        logger.info("-" * 40)
        logger.info("任务状态统计:")
        logger.info(f"  - 重复（已存在）: {self.stats['duplicates']} ({self.stats['duplicates']/self.stats['submitted']*100:.1f}%)")
        logger.info(f"  - 待验证: {self.stats['pending_verification']} ({self.stats['pending_verification']/self.stats['submitted']*100:.1f}%)")
        logger.info(f"  - 新建成功: {self.stats['created']} ({self.stats['created']/self.stats['submitted']*100:.1f}%)")
        logger.info(f"  - 错误: {self.stats['errors']} ({self.stats['errors']/self.stats['submitted']*100:.1f}%)")

        if self.stats['pending_verification'] > 0:
            logger.info("-" * 40)
            logger.info(f"✨ {self.stats['pending_verification']} 个任务进入验证流程")
            logger.info("这些任务将通过验证机制复用已有结果，大幅节省计算资源")

            # 显示前5个验证任务
            if self.stats['verification_tasks']:
                logger.info("\n待验证任务示例（前5个）:")
                for i, task in enumerate(self.stats['verification_tasks'][:5], 1):
                    logger.info(f"  {i}. {task['error_id']}")
                    logger.info(f"     {task['message']}")

    def save_results(self):
        """保存提交结果到文件"""
        output_dir = "/home/shiptux/git/gitee/compass-ci/container/bisect/logs"
        os.makedirs(output_dir, exist_ok=True)

        timestamp = time.strftime("%Y%m%d_%H%M%S")
        output_file = os.path.join(output_dir, f"api_submission_results_{timestamp}.json")

        try:
            with open(output_file, 'w') as f:
                json.dump(self.stats, f, indent=2, ensure_ascii=False)

            logger.info(f"\n提交结果已保存到: {output_file}")

            # 保存验证任务列表
            if self.stats['verification_tasks']:
                verify_file = os.path.join(output_dir, f"pending_verification_{timestamp}.json")
                with open(verify_file, 'w') as f:
                    json.dump(self.stats['verification_tasks'], f, indent=2, ensure_ascii=False)
                logger.info(f"待验证任务列表已保存到: {verify_file}")

        except Exception as e:
            logger.error(f"保存结果失败: {str(e)}")


def main():
    """主函数"""
    import argparse

    parser = argparse.ArgumentParser(description="通过API批量提交bisect任务")
    parser.add_argument("--api-url", default="http://localhost:5000",
                        help="API基础URL (默认: http://localhost:5000)")
    parser.add_argument("--task-file", default="/home/shiptux/git/gitee/compass-ci/new_bisect_tasks.txt",
                        help="任务文件路径")
    parser.add_argument("--dry-run", action="store_true",
                        help="模拟运行，不实际提交")
    parser.add_argument("--batch-size", type=int, default=10,
                        help="每批次提交数量 (默认: 10)")
    parser.add_argument("--delay", type=float, default=0.1,
                        help="批次间延迟（秒）(默认: 0.1)")

    args = parser.parse_args()

    # 检查任务文件
    if not os.path.exists(args.task_file):
        logger.error(f"任务文件不存在: {args.task_file}")
        sys.exit(1)

    # 创建提交器并运行
    submitter = APITaskSubmitter(args.api_url, args.task_file)

    try:
        submitter.run_submission(
            dry_run=args.dry_run,
            batch_size=args.batch_size,
            delay=args.delay
        )

        logger.info("\n批量提交完成!")

        if submitter.stats['pending_verification'] > 0:
            logger.info(f"\n🎯 成功触发 {submitter.stats['pending_verification']} 个验证任务!")
            logger.info("验证消费者将自动处理这些任务，复用已有的bisect结果。")

    except KeyboardInterrupt:
        logger.warning("\n提交被用户中断")
    except Exception as e:
        logger.error(f"提交失败: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())
        sys.exit(1)


if __name__ == "__main__":
    main()