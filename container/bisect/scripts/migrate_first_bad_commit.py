#!/usr/bin/env python3
"""
数据迁移脚本：分离 first_bad_commit 字段

将包含 "SHA + subject" 的 first_bad_commit 分离为：
- first_bad_commit: 纯 SHA (40字符)
- j.first_bad_commit_subject: commit subject
- j.change_point: SHA + subject (用于显示)

用法：
    # 检查需要迁移的任务（dry-run）
    python3 migrate_first_bad_commit.py --dry-run

    # 执行迁移
    python3 migrate_first_bad_commit.py

    # 迁移指定数量的任务
    python3 migrate_first_bad_commit.py --limit 100

    # 使用指定的 ManticoreSearch 主机
    python3 migrate_first_bad_commit.py --host localhost:9308
"""

import os
import sys
import re
import json
import time
import argparse
from typing import Dict, List, Tuple, Optional

# 添加项目路径
sys.path.append(os.environ.get('CCI_SRC', '/srv/cci') + '/container/bisect/lib')
sys.path.append(os.environ.get('LKP_SRC', '/srv/lkp') + '/programs/bisect-py/')

from log_config import logger
from manticore_simple import ManticoreClient


class FirstBadCommitMigrator:
    """first_bad_commit 字段迁移器"""

    def __init__(self, host: str = None, dry_run: bool = False):
        """
        初始化迁移器

        Args:
            host: ManticoreSearch 主机地址
            dry_run: 是否只检查不修改
        """
        self.dry_run = dry_run
        self.client = ManticoreClient(host or os.environ.get('MANTICORE_HOST', 'localhost:9308'))

        # 统计信息
        self.stats = {
            'total_checked': 0,
            'need_migration': 0,
            'already_migrated': 0,
            'migrated': 0,
            'failed': 0,
            'skipped': 0
        }

    def is_commit_hash(self, text: str) -> bool:
        """
        判断是否为有效的 git commit hash (40个十六进制字符)

        Args:
            text: 待检查的文本

        Returns:
            bool: 是否为有效的 commit hash
        """
        if not text or len(text) != 40:
            return False
        return bool(re.match(r'^[a-f0-9]{40}$', text, re.IGNORECASE))

    def parse_first_bad_commit(self, first_bad_commit: str) -> Tuple[Optional[str], Optional[str]]:
        """
        解析 first_bad_commit 字段，分离 SHA 和 subject

        Args:
            first_bad_commit: 原始字段值

        Returns:
            (sha, subject): 分离后的 SHA 和 subject，如果无法分离返回 (None, None)
        """
        if not first_bad_commit or not isinstance(first_bad_commit, str):
            return None, None

        # 如果长度正好是 40，可能是纯 SHA（已迁移）
        if len(first_bad_commit) == 40:
            if self.is_commit_hash(first_bad_commit):
                return first_bad_commit, ""
            else:
                # 不是有效的 hash，可能是异常数据
                return None, None

        # 如果长度小于 40，肯定不是完整的 commit hash
        if len(first_bad_commit) < 40:
            return None, None

        # 尝试提取前 40 个字符作为 SHA
        potential_sha = first_bad_commit[:40]
        if not self.is_commit_hash(potential_sha):
            return None, None

        # 提取 subject（跳过 SHA 后的空格）
        remaining = first_bad_commit[40:].strip()

        return potential_sha, remaining

    def check_task_needs_migration(self, task: Dict) -> Tuple[bool, str]:
        """
        检查任务是否需要迁移

        Args:
            task: 任务数据

        Returns:
            (needs_migration, reason): 是否需要迁移及原因
        """
        task_id = task.get('id')
        first_bad_commit = task.get('first_bad_commit', '')

        # 解析 j 字段
        j_field = task.get('j', {})
        if isinstance(j_field, str):
            try:
                j_field = json.loads(j_field) if j_field else {}
            except:
                j_field = {}

        # 检查是否已经迁移（有 change_point 字段）
        if j_field.get('change_point'):
            return False, "已有 change_point 字段"

        # 检查是否已经迁移（有 first_bad_commit_subject 字段）
        if j_field.get('first_bad_commit_subject') is not None:
            return False, "已有 first_bad_commit_subject 字段"

        # 尝试解析 first_bad_commit
        sha, subject = self.parse_first_bad_commit(first_bad_commit)

        if sha is None:
            return False, f"无法解析 first_bad_commit (长度: {len(first_bad_commit) if first_bad_commit else 0})"

        # 如果只有 SHA 没有 subject，也需要迁移（添加空的 subject 字段）
        if not subject:
            return True, "纯 SHA，需要添加 subject 字段"

        # 有 subject，需要迁移
        return True, f"需要分离 (SHA + subject 长度: {len(first_bad_commit)})"

    def migrate_task(self, task: Dict) -> bool:
        """
        迁移单个任务

        Args:
            task: 任务数据

        Returns:
            bool: 是否成功
        """
        task_id = task.get('id')
        first_bad_commit = task.get('first_bad_commit', '')

        try:
            # 解析
            sha, subject = self.parse_first_bad_commit(first_bad_commit)

            if sha is None:
                logger.error(f"任务 {task_id} 无法解析 first_bad_commit: {first_bad_commit}")
                return False

            # 构造 change_point（用于显示）
            if subject:
                change_point = f"{sha} {subject}"
            else:
                change_point = sha

            # 解析现有的 j 字段
            j_field = task.get('j', {})
            if isinstance(j_field, str):
                try:
                    j_field = json.loads(j_field) if j_field else {}
                except:
                    j_field = {}
            elif not isinstance(j_field, dict):
                j_field = {}

            # 更新 j 字段
            j_field['first_bad_commit_subject'] = subject
            j_field['change_point'] = change_point
            j_field['_migrated_at'] = int(time.time())
            j_field['_migration_source'] = 'migrate_first_bad_commit.py'

            # 准备更新文档
            update_doc = {
                "first_bad_commit": sha,  # 更新为纯 SHA
                "updated_at": int(time.time()),
                "j": j_field
            }

            if self.dry_run:
                logger.info(
                    f"[DRY-RUN] 任务 {task_id}:\n"
                    f"  原值: {first_bad_commit}\n"
                    f"  SHA: {sha}\n"
                    f"  Subject: {subject}\n"
                    f"  Change Point: {change_point}"
                )
                return True

            # 执行更新
            result = self.client.update("bisect", task_id, update_doc)

            if result:
                logger.info(
                    f"✓ 任务 {task_id} 迁移成功\n"
                    f"  SHA: {sha}\n"
                    f"  Subject: {subject[:50]}{'...' if len(subject) > 50 else ''}"
                )
                return True
            else:
                logger.error(f"✗ 任务 {task_id} 更新失败")
                return False

        except Exception as e:
            logger.error(f"✗ 任务 {task_id} 迁移异常: {str(e)}")
            return False

    def scan_and_migrate(self, limit: int = None, batch_size: int = 100):
        """
        扫描并迁移需要迁移的任务

        Args:
            limit: 最多迁移多少个任务（None 表示全部）
            batch_size: 每批查询多少个任务
        """
        logger.info("=" * 80)
        logger.info("开始扫描需要迁移的任务...")
        logger.info(f"模式: {'DRY-RUN（仅检查）' if self.dry_run else '实际迁移'}")
        if limit:
            logger.info(f"限制: 最多处理 {limit} 个任务")
        logger.info("=" * 80)

        offset = 0
        migrated_count = 0

        while True:
            # 查询 success 状态的任务
            query = f"""
                SELECT id, first_bad_commit, j
                FROM bisect
                WHERE bisect_status = 'success'
                ORDER BY id DESC
                LIMIT {batch_size}
                OFFSET {offset}
            """

            tasks = self.client.sql_select(query)

            if not tasks:
                logger.info("没有更多任务")
                break

            logger.info(f"\n处理批次 {offset // batch_size + 1}: {len(tasks)} 个任务")

            for task in tasks:
                self.stats['total_checked'] += 1

                # 检查是否需要迁移
                needs_migration, reason = self.check_task_needs_migration(task)

                if not needs_migration:
                    self.stats['already_migrated'] += 1
                    logger.debug(f"跳过任务 {task.get('id')}: {reason}")
                    continue

                self.stats['need_migration'] += 1
                logger.info(f"任务 {task.get('id')}: {reason}")

                # 检查是否达到限制
                if limit and migrated_count >= limit:
                    logger.info(f"\n已达到迁移限制 ({limit})，停止")
                    self.print_stats()
                    return

                # 执行迁移
                if self.migrate_task(task):
                    self.stats['migrated'] += 1
                    migrated_count += 1
                else:
                    self.stats['failed'] += 1

            offset += batch_size

            # 打印进度
            if offset % (batch_size * 10) == 0:
                logger.info(f"\n进度: 已检查 {self.stats['total_checked']} 个任务，迁移 {self.stats['migrated']} 个")

        logger.info("\n扫描完成")
        self.print_stats()

    def print_stats(self):
        """打印统计信息"""
        logger.info("\n" + "=" * 80)
        logger.info("迁移统计")
        logger.info("=" * 80)
        logger.info(f"总检查任务数:     {self.stats['total_checked']}")
        logger.info(f"已迁移(跳过):     {self.stats['already_migrated']}")
        logger.info(f"需要迁移:         {self.stats['need_migration']}")
        logger.info(f"成功迁移:         {self.stats['migrated']}")
        logger.info(f"失败:             {self.stats['failed']}")
        logger.info("=" * 80)

        if self.dry_run:
            logger.info("\n⚠️  这是 DRY-RUN 模式，没有实际修改数据")
            logger.info("执行迁移请运行: python3 migrate_first_bad_commit.py")


def main():
    """主函数"""
    parser = argparse.ArgumentParser(
        description='迁移 first_bad_commit 字段，分离 SHA 和 subject',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 检查需要迁移的任务（不修改数据）
  python3 migrate_first_bad_commit.py --dry-run

  # 执行迁移（所有任务）
  python3 migrate_first_bad_commit.py

  # 迁移前 100 个任务
  python3 migrate_first_bad_commit.py --limit 100

  # 指定 ManticoreSearch 主机
  python3 migrate_first_bad_commit.py --host localhost:9308
        """
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='只检查不修改数据'
    )

    parser.add_argument(
        '--limit',
        type=int,
        help='最多迁移多少个任务'
    )

    parser.add_argument(
        '--host',
        type=str,
        help='ManticoreSearch 主机地址 (默认: localhost:9308)'
    )

    parser.add_argument(
        '--batch-size',
        type=int,
        default=100,
        help='每批查询多少个任务 (默认: 100)'
    )

    args = parser.parse_args()

    # 创建迁移器
    migrator = FirstBadCommitMigrator(
        host=args.host,
        dry_run=args.dry_run
    )

    # 执行迁移
    try:
        migrator.scan_and_migrate(
            limit=args.limit,
            batch_size=args.batch_size
        )
    except KeyboardInterrupt:
        logger.info("\n\n用户中断迁移")
        migrator.print_stats()
        sys.exit(1)
    except Exception as e:
        logger.error(f"\n迁移过程异常: {str(e)}")
        import traceback
        traceback.print_exc()
        migrator.print_stats()
        sys.exit(1)


if __name__ == '__main__':
    main()
