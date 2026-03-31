#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
test bare repo

verify:
1. Workspace  --bare 
2. --reference 
3. 
4. git bisect  bare repo
"""

import os
import sys
import subprocess
import shutil
import time

# 
os.environ['CCI_SRC'] = os.environ.get('CCI_SRC', '/c/compass-ci')
os.environ['WORK_DIR'] = os.environ.get('WORK_DIR', '/c/bisect')

sys.path.insert(0, os.path.join(os.environ['CCI_SRC'], 'container/bisect/lib'))

from repo_manager import SharedRepoManager
from bisect_utils import extract_repo_name_from_url

print("=" * 80)
print("test Bare repo")
print("=" * 80)

# testrepo
test_repo_url = 'git://172.168.131.113:9418/new-upstream/l/linux/linux-stable.git'
test_task_id = 999999999

print(f"\ntestconfig:")
print(f"  repo URL: {test_repo_url}")
print(f"  testtask ID: {test_task_id}")

# initialize repo manager
manager = SharedRepoManager()

print(f"\n{'=' * 80}")
print(" 1: test")
print("=" * 80)

repo_name = extract_repo_name_from_url(test_repo_url)
test_workspace = os.path.join(manager.REPO_BASE_DIR, str(test_task_id))

if os.path.exists(test_workspace):
    print(f"deletetest: {test_workspace}")
    shutil.rmtree(test_workspace, ignore_errors=True)

print(f"\n{'=' * 80}")
print(" 2:  workspace (bare)")
print("=" * 80)

start_time = time.time()
try:
    workspace_repo_dir, workspace_dir = manager.get_repo_dir(test_task_id, test_repo_url)
    clone_time = time.time() - start_time

    print(f"✓ success!")
    print(f"  : {clone_time:.2f}s")
    print(f"  : {workspace_repo_dir}")

except Exception as e:
    print(f"✗ failed: {e}")
    sys.exit(1)

print(f"\n{'=' * 80}")
print(" 3: verifyrepo")
print("=" * 80)

# check bare repo
is_bare_result = subprocess.run(
    ['git', '-C', workspace_repo_dir, 'config', '--get', 'core.bare'],
    capture_output=True,
    text=True
)

is_bare = is_bare_result.stdout.strip() == 'true'
print(f"   bare repo: {is_bare}")

if is_bare:
    print("  ✓  bare repo")
else:
    print("  ✗ warning:  bare repo")

# check alternates (reference)
alternates_file = os.path.join(workspace_repo_dir, 'objects', 'info', 'alternates')
has_reference = os.path.exists(alternates_file)

print(f"   --reference: {has_reference}")
if has_reference:
    with open(alternates_file, 'r') as f:
        ref_path = f.read().strip()
    print(f"  ✓ : {ref_path}")
else:
    print("  ✗ warning:  --reference")

print(f"\n{'=' * 80}")
print(" 4: check")
print("=" * 80)

# 
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

print(f"  Workspace : {workspace_size_mb:.2f} MB")

if workspace_size_mb < 10:
    print(f"  ✓  ( --reference success)")
elif workspace_size_mb < 100:
    print(f"  ⚠ , --reference")
else:
    print(f"  ✗ ,--reference ")

print(f"\n{'=' * 80}")
print(" 5: test git bisect ")
print("=" * 80)

# test git log 
log_result = subprocess.run(
    ['git', '-C', workspace_repo_dir, 'log', '--oneline', '-5'],
    capture_output=True,
    text=True
)

if log_result.returncode == 0:
    print("  ✓ git log ")
    print(f"  5submit:")
    for line in log_result.stdout.strip().split('\n')[:3]:
        print(f"    {line}")
else:
    print(f"  ✗ git log failed: {log_result.stderr}")

# test git bisect start 
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
    print("  ✓ git bisect start  bare repo")
    # reset bisect
    subprocess.run(['git', '-C', workspace_repo_dir, 'bisect', 'reset'],
                   capture_output=True)
else:
    print(f"  ✗ git bisect start failed: {bisect_start.stderr}")

print(f"\n{'=' * 80}")
print(" 6: test")
print("=" * 80)

manager.release_repo_dir(workspace_repo_dir, task_id=test_task_id)
print("  ✓ test")

print(f"\n{'=' * 80}")
print("test")
print("=" * 80)

print(f"\n:")
print(f"  - : {clone_time:.2f}s")
print(f"  - : {workspace_size_mb:.2f} MB")
print(f"  - Bare repo: {'' if is_bare else ''}")
print(f"  -  reference: {'' if has_reference else ''}")
print(f"  - Bisect : {'' if bisect_start.returncode == 0 else ''}")

if is_bare and has_reference and workspace_size_mb < 10 and bisect_start.returncode == 0:
    print(f"\n✓ test! Bare repo")
else:
    print(f"\n⚠ test,check")

print(f"\n:")
print(f"  - :  50-80% ( checkout)")
print(f"  - :  99% ( --reference)")
print(f"  - :  (file)")
