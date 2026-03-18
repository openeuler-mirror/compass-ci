#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
test commit time service  bisect_producer 

verify:
1. 
2. CommitTimeClient initialize
3. extract_commit_from_full_text_kv 
4. is_commit_too_old 
"""

import os
import sys

# 
os.environ['CCI_SRC'] = os.environ.get('CCI_SRC', '/c/compass-ci')
os.environ['WORK_DIR'] = os.environ.get('WORK_DIR', '/c/bisect')

# 
sys.path.insert(0, os.path.join(os.environ['CCI_SRC'], 'container/bisect/lib'))
sys.path.insert(0, os.path.join(os.environ['CCI_SRC'], 'container/bisect/services/commit_time_service'))

print("=" * 60)
print("test Commit Time Service ")
print("=" * 60)

# test 1: 
print("\n[test 1] ...")
try:
    from client import CommitTimeClient
    from bisect_utils import extract_commit_from_full_text_kv
    print("✓ success")
except ImportError as e:
    print(f"✗ failed: {e}")
    sys.exit(1)

# test 2: initialize
print("\n[test 2] initialize CommitTimeClient...")
try:
    # service URL
    service_url = os.environ.get('COMMIT_TIME_SERVICE_URL', 'http://localhost:8765')
    client = CommitTimeClient(service_url, timeout=5)
    print(f"✓ initializesuccess | URL: {service_url}")
except Exception as e:
    print(f"✗ initializefailed: {e}")
    sys.exit(1)

# test 3: checkservicestatus
print("\n[test 3] checkservicestatus...")
try:
    is_healthy = client.health_check()
    if is_healthy:
        print("✓ service")
    else:
        print("⚠ service (，)")
except Exception as e:
    print(f"⚠ checkfailed: {e} (，)")

# test 4: test commit 
print("\n[test 4] test extract_commit_from_full_text_kv...")
test_cases = [
    {
        'input': 'commit: 5e5d40e65cb55e4699c9879674a004f246606a8d',
        'expected': '5e5d40e65cb55e4699c9879674a004f246606a8d',
        'desc': 'commit: '
    },
    {
        'input': 'commit=abc123def456789',
        'expected': 'abc123def456789',
        'desc': 'commit= '
    },
    {
        'input': 'HEAD: 1234567890abcdef1234567890abcdef12345678',
        'expected': '1234567890abcdef1234567890abcdef12345678',
        'desc': 'HEAD: '
    },
    {
        'input': 'no commit here',
        'expected': '',
        'desc': ' commit'
    }
]

for i, test in enumerate(test_cases, 1):
    result = extract_commit_from_full_text_kv(test['input'])
    if result == test['expected']:
        print(f"  ✓  {i}: {test['desc']}")
    else:
        print(f"  ✗  {i}: {test['desc']}")
        print(f"    : {test['expected']}")
        print(f"    : {result}")

# test 5: test is_commit_too_old ()
print("\n[test 5] test is_commit_too_old ()...")
try:
    # service， False ()
    is_old = client.is_commit_too_old(
        'https://gitee.com/openeuler/kernel.git',
        'invalid_commit',
        365
    )
    print(f"  test: is_old={is_old} ( False)")
    if is_old == False:
        print("  ✓ ")
    else:
        print("  ✗ ")
except Exception as e:
    print(f"  ⚠ exception: {e}")

print("\n" + "=" * 60)
print("testcompleted")
print("=" * 60)
print("\n:")
print("- servicecheckfailed，（service）")
print("- ，service")
print("- test")
