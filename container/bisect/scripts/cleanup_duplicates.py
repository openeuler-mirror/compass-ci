#!/usr/bin/env python3
"""
清理 bisect 表中的重复数据

策略：
1. 对于相同 error_id 的任务，保留"最有价值"的一个
2. 价值排序：success > verifying > processing > wait > failed
3. 同等状态下保留最新的（submit_time 最大）

使用方式：
    # 预览模式（不实际删除）
    python cleanup_duplicates.py --dry-run

    # 实际执行
    python cleanup_duplicates.py

    # 清理指定天数前的老任务
    python cleanup_duplicates.py --clean-old-days 90
"""

import os
import sys
import argparse
import time
from collections import defaultdict

sys.path.append(os.environ.get('LKP_SRC', '/lkp') + '/programs/bisect-py/')
from manticore_simple import ManticoreClient

sys.path.append(os.environ.get('CCI_SRC', '/c/compass-ci') + '/container/bisect/lib')
from config import Config


# 状态优先级（数字越大越优先保留）
STATUS_PRIORITY = {
    'success': 5,
    'verifying': 4,
    'processing': 3,
    'pending_verification': 2,
    'wait': 1,
    'failed': 0
}


def get_client():
    """获取 ManticoreSearch 客户端"""
    return ManticoreClient(
        host=os.environ.get('MANTICORE_HOST', 'localhost'),
        port=int(os.environ.get('MANTICORE_WRITE_PORT', '9308'))
    )


def find_duplicates(client, batch_size=10000):
    """查找重复的 error_id"""
    print("=" * 60)
    print("Step 1: 查找重复的 error_id")
    print("=" * 60)

    # 查询所有有 error_id 的任务
    offset = 0
    all_tasks = []

    while True:
        query = f"""
            SELECT id, error_id, bisect_status, submit_time, bad_job_id
            FROM bisect
            WHERE error_id != ''
            ORDER BY id ASC
            LIMIT {batch_size}
            OFFSET {offset}
        """
        result = client.sql_select(query)
        if not result:
            break

        all_tasks.extend(result)
        offset += batch_size
        print(f"  已查询 {len(all_tasks)} 条记录...")

        if len(result) < batch_size:
            break

    print(f"  总计: {len(all_tasks)} 条带 error_id 的任务")

    # 按 error_id 分组
    groups = defaultdict(list)
    for task in all_tasks:
        error_id = task.get('error_id', '')
        if error_id:
            groups[error_id].append(task)

    # 找出重复的
    duplicates = {k: v for k, v in groups.items() if len(v) > 1}

    print(f"  唯一 error_id: {len(groups)} 个")
    print(f"  重复 error_id: {len(duplicates)} 个")

    # 统计重复数量分布
    dup_counts = defaultdict(int)
    for tasks in duplicates.values():
        dup_counts[len(tasks)] += 1

    if dup_counts:
        print("\n  重复数量分布:")
        for count, num in sorted(dup_counts.items()):
            print(f"    {count} 个重复: {num} 组")

    return duplicates


def select_task_to_keep(tasks):
    """从重复任务中选择要保留的一个

    策略：
    1. 优先保留状态更好的（success > verifying > ... > failed）
    2. 同等状态下保留 submit_time 最新的
    """
    def sort_key(task):
        status = task.get('bisect_status', 'wait')
        priority = STATUS_PRIORITY.get(status, 0)
        submit_time = task.get('submit_time', 0) or 0
        return (priority, submit_time)

    sorted_tasks = sorted(tasks, key=sort_key, reverse=True)
    return sorted_tasks[0]  # 返回最优先保留的


def cleanup_duplicates(client, duplicates, dry_run=True):
    """清理重复数据"""
    print("\n" + "=" * 60)
    print(f"Step 2: 清理重复数据 ({'预览模式' if dry_run else '实际执行'})")
    print("=" * 60)

    total_to_delete = 0
    ids_to_delete = []

    for error_id, tasks in duplicates.items():
        keep_task = select_task_to_keep(tasks)
        keep_id = keep_task['id']

        delete_tasks = [t for t in tasks if t['id'] != keep_id]
        total_to_delete += len(delete_tasks)

        for task in delete_tasks:
            ids_to_delete.append(task['id'])

        # 打印详情（只打印前 10 组）
        if len(ids_to_delete) <= 50:
            print(f"\n  error_id: {error_id[:80]}...")
            print(f"    保留: id={keep_id}, status={keep_task.get('bisect_status')}, "
                  f"submit_time={keep_task.get('submit_time')}")
            for task in delete_tasks:
                print(f"    删除: id={task['id']}, status={task.get('bisect_status')}, "
                      f"submit_time={task.get('submit_time')}")

    print(f"\n  总计需要删除: {total_to_delete} 条记录")

    if dry_run:
        print("\n  [预览模式] 未实际删除任何数据")
        print("  使用 --execute 参数执行实际删除")
        return 0

    # 实际删除（分批执行）
    batch_size = Config.BATCH_DELETE_SIZE
    deleted = 0

    for i in range(0, len(ids_to_delete), batch_size):
        batch_ids = ids_to_delete[i:i + batch_size]
        ids_str = ','.join(map(str, batch_ids))

        delete_query = f"DELETE FROM bisect WHERE id IN ({ids_str})"
        try:
            client.sql_raw(delete_query)
            deleted += len(batch_ids)
            print(f"  已删除: {deleted}/{total_to_delete}")
        except Exception as e:
            print(f"  删除失败: {str(e)}")

    print(f"\n  实际删除: {deleted} 条记录")
    return deleted


def cleanup_old_tasks(client, days, dry_run=True):
    """清理老旧任务"""
    print("\n" + "=" * 60)
    print(f"Step 3: 清理 {days} 天前的老任务 ({'预览模式' if dry_run else '实际执行'})")
    print("=" * 60)

    threshold = int(time.time()) - days * 86400
    threshold_date = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(threshold))
    print(f"  时间阈值: {threshold_date}")

    # 只清理 wait 和 failed 状态的老任务（保留 success/verifying）
    statuses_to_clean = ['wait', 'failed']

    for status in statuses_to_clean:
        count_query = f"""
            SELECT COUNT(*) as count
            FROM bisect
            WHERE bisect_status = '{status}'
            AND submit_time < {threshold}
            AND submit_time > 0
        """
        result = client.sql_select(count_query)
        count = result[0]['count'] if result else 0

        print(f"\n  {status} 状态老任务: {count} 条")

        if count == 0:
            continue

        if dry_run:
            print(f"    [预览模式] 未实际删除")
            continue

        # 实际删除
        delete_query = f"""
            DELETE FROM bisect
            WHERE bisect_status = '{status}'
            AND submit_time < {threshold}
            AND submit_time > 0
        """
        try:
            client.sql_raw(delete_query)
            print(f"    已删除 {count} 条 {status} 任务")
        except Exception as e:
            print(f"    删除失败: {str(e)}")


def show_statistics(client):
    """显示当前数据统计"""
    print("\n" + "=" * 60)
    print("当前数据统计")
    print("=" * 60)

    # 按状态统计
    query = """
        SELECT bisect_status, COUNT(*) as count
        FROM bisect
        GROUP BY bisect_status
        ORDER BY count DESC
    """
    result = client.sql_select(query)
    if result:
        print("\n  按状态统计:")
        total = 0
        for row in result:
            status = row.get('bisect_status', 'unknown')
            count = row.get('count', 0)
            total += count
            print(f"    {status}: {count}")
        print(f"    --------")
        print(f"    总计: {total}")

    # 按月份统计
    # ManticoreSearch 不支持 FROM_UNIXTIME，用简单查询代替
    query = """
        SELECT MIN(submit_time) as oldest, MAX(submit_time) as newest
        FROM bisect
        WHERE submit_time > 0
    """
    result = client.sql_select(query)
    if result and result[0].get('oldest'):
        oldest = time.strftime('%Y-%m-%d', time.localtime(result[0]['oldest']))
        newest = time.strftime('%Y-%m-%d', time.localtime(result[0]['newest']))
        print(f"\n  时间范围: {oldest} 至 {newest}")


def main():
    parser = argparse.ArgumentParser(description='清理 bisect 表中的重复和老旧数据')
    parser.add_argument('--execute', action='store_true',
                        help='实际执行删除（默认为预览模式）')
    parser.add_argument('--clean-old-days', type=int, default=0,
                        help='清理 N 天前的 wait/failed 任务（0 表示不清理）')
    parser.add_argument('--stats-only', action='store_true',
                        help='只显示统计信息，不做任何清理')

    args = parser.parse_args()
    dry_run = not args.execute

    client = get_client()

    # 显示统计
    show_statistics(client)

    if args.stats_only:
        return

    # 查找并清理重复数据
    duplicates = find_duplicates(client)
    if duplicates:
        cleanup_duplicates(client, duplicates, dry_run=dry_run)

    # 清理老任务
    if args.clean_old_days > 0:
        cleanup_old_tasks(client, args.clean_old_days, dry_run=dry_run)

    if dry_run:
        print("\n" + "=" * 60)
        print("以上为预览结果，使用 --execute 参数执行实际删除")
        print("=" * 60)


if __name__ == '__main__':
    main()
