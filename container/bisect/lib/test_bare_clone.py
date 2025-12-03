#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
测试 bare 仓库克隆优化

验证:
1. Workspace 使用 --bare 克隆
2. --reference 正确工作
3. 磁盘占用显著减少
4. git bisect 可以在 bare 仓库中运行
"""

import os
import sys
import subprocess
import shutil
import time

# 设置环境
os.environ['CCI_SRC'] = os.environ.get('CCI_SRC', '/c/compass-ci')
os.environ['WORK_DIR'] = os.environ.get('WORK_DIR', '/c/bisect')

sys.path.insert(0, os.path.join(os.environ['CCI_SRC'], 'container/bisect/lib'))

from repo_manager import SharedRepoManager
from bisect_utils import extract_repo_name_from_url

print("=" * 80)
print("测试 Bare 仓库克隆优化")
print("=" * 80)

# 测试仓库
test_repo_url = 'git://172.168.131.113:9418/new-upstream/l/linux/linux-stable.git'
test_task_id = 999999999

print(f"\n测试配置:")
print(f"  仓库 URL: {test_repo_url}")
print(f"  测试任务 ID: {test_task_id}")

# 初始化 repo manager
manager = SharedRepoManager()

print(f"\n{'=' * 80}")
print("步骤 1: 清理旧的测试数据")
print("=" * 80)

repo_name = extract_repo_name_from_url(test_repo_url)
test_workspace = os.path.join(manager.REPO_BASE_DIR, str(test_task_id))

if os.path.exists(test_workspace):
    print(f"删除旧的测试工作区: {test_workspace}")
    shutil.rmtree(test_workspace, ignore_errors=True)

print(f"\n{'=' * 80}")
print("步骤 2: 克隆 workspace (bare)")
print("=" * 80)

start_time = time.time()
try:
    workspace_repo_dir, workspace_dir = manager.get_repo_dir(test_task_id, test_repo_url)
    clone_time = time.time() - start_time

    print(f"✓ 克隆成功!")
    print(f"  耗时: {clone_time:.2f}s")
    print(f"  路径: {workspace_repo_dir}")

except Exception as e:
    print(f"✗ 克隆失败: {e}")
    sys.exit(1)

print(f"\n{'=' * 80}")
print("步骤 3: 验证仓库类型")
print("=" * 80)

# 检查是否是 bare 仓库
is_bare_result = subprocess.run(
    ['git', '-C', workspace_repo_dir, 'config', '--get', 'core.bare'],
    capture_output=True,
    text=True
)

is_bare = is_bare_result.stdout.strip() == 'true'
print(f"  是否为 bare 仓库: {is_bare}")

if is_bare:
    print("  ✓ 正确使用了 bare 仓库")
else:
    print("  ✗ 警告: 不是 bare 仓库")

# 检查是否使用了 alternates (reference)
alternates_file = os.path.join(workspace_repo_dir, 'objects', 'info', 'alternates')
has_reference = os.path.exists(alternates_file)

print(f"  使用 --reference: {has_reference}")
if has_reference:
    with open(alternates_file, 'r') as f:
        ref_path = f.read().strip()
    print(f"  ✓ 引用路径: {ref_path}")
else:
    print("  ✗ 警告: 未使用 --reference")

print(f"\n{'=' * 80}")
print("步骤 4: 检查磁盘占用")
print("=" * 80)

# 计算目录大小
def get_dir_size(path):
    total = 0
    for dirpath, dirnames, filenames in os.walk(path):
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            if os.path.exists(filepath):
                total += os.path.getsize(filepath)
    return total

workspace_size = get_dir_size(workspace_repo_dir)
workspace_size_mb = workspace_size / (1024 * 1024)

print(f"  Workspace 大小: {workspace_size_mb:.2f} MB")

if workspace_size_mb < 10:
    print(f"  ✓ 磁盘占用极小 (使用 --reference 成功)")
elif workspace_size_mb < 100:
    print(f"  ⚠ 磁盘占用较小,但可能未完全利用 --reference")
else:
    print(f"  ✗ 磁盘占用过大,--reference 可能未生效")

print(f"\n{'=' * 80}")
print("步骤 5: 测试 git bisect 兼容性")
print("=" * 80)

# 测试 git log 是否工作
log_result = subprocess.run(
    ['git', '-C', workspace_repo_dir, 'log', '--oneline', '-5'],
    capture_output=True,
    text=True
)

if log_result.returncode == 0:
    print("  ✓ git log 正常工作")
    print(f"  最近5个提交:")
    for line in log_result.stdout.strip().split('\n')[:3]:
        print(f"    {line}")
else:
    print(f"  ✗ git log 失败: {log_result.stderr}")

# 测试 git bisect start 是否工作
bisect_result = subprocess.run(
    ['git', '-C', workspace_repo_dir, 'bisect', 'reset'],
    capture_output=True,
    text=True
)

bisect_start = subprocess.run(
    ['git', '-C', workspace_repo_dir, 'bisect', 'start'],
    capture_output=True,
    text=True
)

if bisect_start.returncode == 0:
    print("  ✓ git bisect start 可以在 bare 仓库中运行")
    # 重置 bisect
    subprocess.run(['git', '-C', workspace_repo_dir, 'bisect', 'reset'],
                   capture_output=True)
else:
    print(f"  ✗ git bisect start 失败: {bisect_start.stderr}")

print(f"\n{'=' * 80}")
print("步骤 6: 清理测试数据")
print("=" * 80)

manager.release_repo_dir(workspace_repo_dir, task_id=test_task_id)
print("  ✓ 测试工作区已清理")

print(f"\n{'=' * 80}")
print("测试总结")
print("=" * 80)

print(f"\n优化效果:")
print(f"  - 克隆耗时: {clone_time:.2f}s")
print(f"  - 磁盘占用: {workspace_size_mb:.2f} MB")
print(f"  - Bare 仓库: {'是' if is_bare else '否'}")
print(f"  - 使用 reference: {'是' if has_reference else '否'}")
print(f"  - Bisect 兼容: {'是' if bisect_start.returncode == 0 else '否'}")

if is_bare and has_reference and workspace_size_mb < 10 and bisect_start.returncode == 0:
    print(f"\n✓ 所有测试通过! Bare 仓库优化工作正常")
else:
    print(f"\n⚠ 部分测试未通过,需要检查")

print(f"\n预期优势:")
print(f"  - 克隆速度: 提升 50-80% (无需 checkout)")
print(f"  - 磁盘占用: 减少 99% (使用 --reference)")
print(f"  - 并发能力: 提升 (无文件系统竞争)")
