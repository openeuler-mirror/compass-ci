#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
测试 commit time service 与 bisect_producer 的集成

验证点:
1. 导入模块正确
2. CommitTimeClient 初始化正常
3. extract_commit_from_full_text_kv 函数工作正常
4. is_commit_too_old 方法返回预期结果
"""

import os
import sys

# 设置环境变量
os.environ['CCI_SRC'] = os.environ.get('CCI_SRC', '/c/compass-ci')
os.environ['WORK_DIR'] = os.environ.get('WORK_DIR', '/c/bisect')

# 添加路径
sys.path.insert(0, os.path.join(os.environ['CCI_SRC'], 'container/bisect/lib'))
sys.path.insert(0, os.path.join(os.environ['CCI_SRC'], 'container/bisect/services/commit_time_service'))

print("=" * 60)
print("测试 Commit Time Service 集成")
print("=" * 60)

# 测试 1: 导入模块
print("\n[测试 1] 导入模块...")
try:
    from client import CommitTimeClient
    from bisect_utils import extract_commit_from_full_text_kv
    print("✓ 导入成功")
except ImportError as e:
    print(f"✗ 导入失败: {e}")
    sys.exit(1)

# 测试 2: 初始化客户端
print("\n[测试 2] 初始化 CommitTimeClient...")
try:
    # 使用本地服务 URL
    service_url = os.environ.get('COMMIT_TIME_SERVICE_URL', 'http://localhost:8765')
    client = CommitTimeClient(service_url, timeout=5)
    print(f"✓ 客户端初始化成功 | URL: {service_url}")
except Exception as e:
    print(f"✗ 客户端初始化失败: {e}")
    sys.exit(1)

# 测试 3: 检查服务健康状态
print("\n[测试 3] 检查服务健康状态...")
try:
    is_healthy = client.health_check()
    if is_healthy:
        print("✓ 服务运行正常")
    else:
        print("⚠ 服务未运行 (这是正常的，如果容器还未启动)")
except Exception as e:
    print(f"⚠ 健康检查失败: {e} (这是正常的，如果容器还未启动)")

# 测试 4: 测试 commit 提取函数
print("\n[测试 4] 测试 extract_commit_from_full_text_kv...")
test_cases = [
    {
        'input': 'commit: 5e5d40e65cb55e4699c9879674a004f246606a8d',
        'expected': '5e5d40e65cb55e4699c9879674a004f246606a8d',
        'desc': 'commit: 格式'
    },
    {
        'input': 'commit=abc123def456789',
        'expected': 'abc123def456789',
        'desc': 'commit= 格式'
    },
    {
        'input': 'HEAD: 1234567890abcdef1234567890abcdef12345678',
        'expected': '1234567890abcdef1234567890abcdef12345678',
        'desc': 'HEAD: 格式'
    },
    {
        'input': 'no commit here',
        'expected': '',
        'desc': '无 commit'
    }
]

for i, test in enumerate(test_cases, 1):
    result = extract_commit_from_full_text_kv(test['input'])
    if result == test['expected']:
        print(f"  ✓ 用例 {i}: {test['desc']}")
    else:
        print(f"  ✗ 用例 {i}: {test['desc']}")
        print(f"    期望: {test['expected']}")
        print(f"    实际: {result}")

# 测试 5: 测试 is_commit_too_old (模拟降级)
print("\n[测试 5] 测试 is_commit_too_old (降级策略)...")
try:
    # 即使服务不可用，也应该返回 False (降级策略)
    is_old = client.is_commit_too_old(
        'https://gitee.com/openeuler/kernel.git',
        'invalid_commit',
        365
    )
    print(f"  降级策略测试: is_old={is_old} (应该是 False)")
    if is_old == False:
        print("  ✓ 降级策略正确工作")
    else:
        print("  ✗ 降级策略未正确工作")
except Exception as e:
    print(f"  ⚠ 异常: {e}")

print("\n" + "=" * 60)
print("集成测试完成")
print("=" * 60)
print("\n提示:")
print("- 如果服务健康检查失败，这是正常的（服务尚未启动）")
print("- 部署容器后，服务将自动启动")
print("- 关键是导入和函数测试应该通过")
