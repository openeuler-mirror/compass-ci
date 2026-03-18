#!/usr/bin/env python3
"""
 bisect duplicate

：
1.  error_id task，""
2. ：success > verifying > processing > wait > failed
3. status（submit_time ）

：
    # （delete）
    python cleanup_duplicates.py --dry-run

    # 
    python cleanup_duplicates.py

    # task
    python cleanup_duplicates.py --clean-old-days 90
"""

import os
import sys
import argparse
import time
from collections import defaultdict

sys.path.append(os.environ.get('LKP_SRC', '/lkp') + '/sbin/bisect/')
from lkp_bisect.db.manticore import ManticoreClient

sys.path.append(os.environ.get('CCI_SRC', '/c/compass-ci') + '/container/bisect/lib')
from config import Config


# status（）
STATUS_PRIORITY = {
    'success': 5,
    'verifying': 4,
    'processing': 3,
    'pending_verification': 2,
    'wait': 1,
    'failed': 0
}


def get_client():
    """get ManticoreSearch """
    return ManticoreClient(
        host=os.environ.get('MANTICORE_HOST', 'localhost'),
        port=int(os.environ.get('MANTICORE_WRITE_PORT', '9308'))
    )


def find_duplicates(client, batch_size=10000):
    """duplicate error_id"""
    print("=" * 60)
    print("Step 1: duplicate error_id")
    print("=" * 60)

    # query error_id task
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
        print(f"  query {len(all_tasks)} ...")

        if len(result) < batch_size:
            break

    print(f"  : {len(all_tasks)}  error_id task")

    #  error_id 
    groups = defaultdict(list)
    for task in all_tasks:
        error_id = task.get('error_id', '')
        if error_id:
            groups[error_id].append(task)

    # duplicate
    duplicates = {k: v for k, v in groups.items() if len(v) > 1}

    print(f"   error_id: {len(groups)} ")
    print(f"  duplicate error_id: {len(duplicates)} ")

    # statsduplicatecount
    dup_counts = defaultdict(int)
    for tasks in duplicates.values():
        dup_counts[len(tasks)] += 1

    if dup_counts:
        print("\n  duplicatecount:")
        for count, num in sorted(dup_counts.items()):
            print(f"    {count} duplicate: {num} ")

    return duplicates


def select_task_to_keep(tasks):
    """duplicatetask

    ：
    1. status（success > verifying > ... > failed）
    2. status submit_time 
    """
    def sort_key(task):
        status = task.get('bisect_status', 'wait')
        priority = STATUS_PRIORITY.get(status, 0)
        submit_time = task.get('submit_time', 0) or 0
        return (priority, submit_time)

    sorted_tasks = sorted(tasks, key=sort_key, reverse=True)
    return sorted_tasks[0]  # 


def cleanup_duplicates(client, duplicates, dry_run=True):
    """duplicate"""
    print("\n" + "=" * 60)
    print(f"Step 2: duplicate ({'' if dry_run else ''})")
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

        # （ 10 ）
        if len(ids_to_delete) <= 50:
            print(f"\n  error_id: {error_id[:80]}...")
            print(f"    : id={keep_id}, status={keep_task.get('bisect_status')}, "
                  f"submit_time={keep_task.get('submit_time')}")
            for task in delete_tasks:
                print(f"    delete: id={task['id']}, status={task.get('bisect_status')}, "
                      f"submit_time={task.get('submit_time')}")

    print(f"\n  delete: {total_to_delete} ")

    if dry_run:
        print("\n  [] delete")
        print("   --execute delete")
        return 0

    # delete（）
    batch_size = Config.BATCH_DELETE_SIZE
    deleted = 0

    for i in range(0, len(ids_to_delete), batch_size):
        batch_ids = ids_to_delete[i:i + batch_size]
        ids_str = ','.join(map(str, batch_ids))

        delete_query = f"DELETE FROM bisect WHERE id IN ({ids_str})"
        try:
            client.sql_raw(delete_query)
            deleted += len(batch_ids)
            print(f"  delete: {deleted}/{total_to_delete}")
        except Exception as e:
            print(f"  deletefailed: {str(e)}")

    print(f"\n  delete: {deleted} ")
    return deleted


def cleanup_old_tasks(client, days, dry_run=True):
    """task"""
    print("\n" + "=" * 60)
    print(f"Step 3:  {days} task ({'' if dry_run else ''})")
    print("=" * 60)

    threshold = int(time.time()) - days * 86400
    threshold_date = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(threshold))
    print(f"  : {threshold_date}")

    #  wait  failed statustask（ success/verifying）
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

        print(f"\n  {status} statustask: {count} ")

        if count == 0:
            continue

        if dry_run:
            print(f"    [] delete")
            continue

        # delete
        delete_query = f"""
            DELETE FROM bisect
            WHERE bisect_status = '{status}'
            AND submit_time < {threshold}
            AND submit_time > 0
        """
        try:
            client.sql_raw(delete_query)
            print(f"    delete {count}  {status} task")
        except Exception as e:
            print(f"    deletefailed: {str(e)}")


def show_statistics(client):
    """stats"""
    print("\n" + "=" * 60)
    print("stats")
    print("=" * 60)

    # statusstats
    query = """
        SELECT bisect_status, COUNT(*) as count
        FROM bisect
        GROUP BY bisect_status
        ORDER BY count DESC
    """
    result = client.sql_select(query)
    if result:
        print("\n  statusstats:")
        total = 0
        for row in result:
            status = row.get('bisect_status', 'unknown')
            count = row.get('count', 0)
            total += count
            print(f"    {status}: {count}")
        print(f"    --------")
        print(f"    : {total}")

    # stats
    # ManticoreSearch support FROM_UNIXTIME，query
    query = """
        SELECT MIN(submit_time) as oldest, MAX(submit_time) as newest
        FROM bisect
        WHERE submit_time > 0
    """
    result = client.sql_select(query)
    if result and result[0].get('oldest'):
        oldest = time.strftime('%Y-%m-%d', time.localtime(result[0]['oldest']))
        newest = time.strftime('%Y-%m-%d', time.localtime(result[0]['newest']))
        print(f"\n  : {oldest}  {newest}")


def main():
    parser = argparse.ArgumentParser(description=' bisect duplicate')
    parser.add_argument('--execute', action='store_true',
                        help='delete（default）')
    parser.add_argument('--clean-old-days', type=int, default=0,
                        help=' N  wait/failed task（0 ）')
    parser.add_argument('--stats-only', action='store_true',
                        help='stats，')

    args = parser.parse_args()
    dry_run = not args.execute

    client = get_client()

    # stats
    show_statistics(client)

    if args.stats_only:
        return

    # duplicate
    duplicates = find_duplicates(client)
    if duplicates:
        cleanup_duplicates(client, duplicates, dry_run=dry_run)

    # task
    if args.clean_old_days > 0:
        cleanup_old_tasks(client, args.clean_old_days, dry_run=dry_run)

    if dry_run:
        print("\n" + "=" * 60)
        print("， --execute delete")
        print("=" * 60)


if __name__ == '__main__':
    main()
