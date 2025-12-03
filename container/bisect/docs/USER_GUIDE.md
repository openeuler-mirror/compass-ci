# Bisect 系统用户指南

## 概述

Bisect 系统是一个自动化的二分查找系统，用于定位代码库中引入问题的第一个坏提交。本指南介绍如何使用和管理 Bisect 系统。

---

## 一、快速开始

### 1.1 系统架构

Bisect 系统包含以下核心组件：

- **Producer** - 自动发现失败任务并创建 bisect 任务
- **Consumer** - 执行二分查找算法
- **Verification** - 验证 bisect 结果的准确性
- **HEAD Check** - 检测已知问题在最新代码中的回归情况

### 1.2 基本工作流程

```
失败任务 → Producer 发现 → 创建 bisect 任务 → Consumer 执行 → 找到坏提交 → Verification 验证 → HEAD 检查
```

---

## 二、Producer 统计查询

### 2.1 目录结构

```
/srv/result/bisect/
├── producer_stats/              # Producer 运行统计
│   ├── producer_latest.txt      # 最新状态摘要（快速查看）
│   ├── 2024-10-20/              # 按日期组织的详细报告
│   │   ├── producer_report_1760971211.txt    # 可读的分步骤报告
│   │   └── producer_stats_1760971211.json    # JSON格式统计数据
│   └── 2024-10-21/
│       └── ...
└── logs/analysis/               # Error ID 筛选分析
    ├── filtered_jobs_20241020_232338.json     # 筛选成功的错误
    ├── unfiltered_jobs_20241020_232338.json   # 被过滤的错误（噪音）
    └── summary_20241020_232338.txt            # 易读的汇总报告
```

### 2.2 快速查询命令

#### 查看最新状态
```bash
cat /srv/result/bisect/producer_stats/producer_latest.txt
```

#### 查看详细报告
```bash
# 查看今天的详细报告
TODAY=$(date +%Y-%m-%d)
cat /srv/result/bisect/producer_stats/$TODAY/producer_report_*.txt
```

#### 查看筛选汇总
```bash
ls -t /srv/result/bisect/logs/analysis/summary_*.txt | head -1 | xargs cat
```

### 2.3 统计指标说明

| 指标 | 说明 | 正常范围 |
|------|------|----------|
| **jobs_processed** | 需要处理的失败 jobs 数量 | 取决于系统规模 |
| **tasks_created_success** | 成功创建的 bisect 任务 | - |
| **转化率** | 创建任务 / 处理 jobs | 成熟系统: 0.5-5%<br>新系统: >5% |
| **筛选效率** | 过滤噪音比例 | 优秀: >90%<br>良好: 80-90% |
| **去重率** | 数据库已存在的比例 | 成熟系统: >80%<br>新系统: <80% |

---

## 三、验证功能配置

### 3.1 核心配置项

#### 并行验证作业数
**配置项：** `PARALLEL_VERIFICATION_JOBS`
**默认值：** 200
**说明：** 同时提交的验证作业数量

```bash
export PARALLEL_VERIFICATION_JOBS=200
```

#### 验证批量大小
**配置项：** `VERIFICATION_BATCH_SIZE`
**默认值：** 200
**说明：** 每次从数据库查询的待验证任务数量

```bash
export VERIFICATION_BATCH_SIZE=200
```

#### HEAD 检查批量大小
**配置项：** `HEAD_CHECK_BATCH_SIZE`
**默认值：** 200
**说明：** 每次扫描的 HEAD 检查任务数量

```bash
export HEAD_CHECK_BATCH_SIZE=200
```

### 3.2 推荐配置

| 环境 | PARALLEL_JOBS | BATCH_SIZE | 说明 |
|------|---------------|------------|------|
| 测试环境 | 10 | 20 | 小规模测试 |
| 生产环境（低峰） | 200 | 200 | 快速处理积压 |
| 生产环境（高峰） | 50 | 100 | 平衡性能 |

### 3.3 启动配置

#### 方式1：环境变量
```bash
# 设置环境变量
export PARALLEL_VERIFICATION_JOBS=200
export VERIFICATION_BATCH_SIZE=200
export HEAD_CHECK_BATCH_SIZE=200

# 启动服务
python3 app/__init__.py
```

#### 方式2：启动脚本
```bash
#!/bin/bash

# 验证配置
export PARALLEL_VERIFICATION_JOBS=200
export VERIFICATION_BATCH_SIZE=200
export HEAD_CHECK_BATCH_SIZE=200

# 其他配置
export BISECT_THREADS=16
export MANTICORE_HOST=localhost
export MANTICORE_WRITE_PORT=9308

# 启动服务
cd /home/shiptux/git/gitee/compass-ci/container/bisect
python3 app/__init__.py
```

---

## 四、验证状态重置

### 4.1 重置脚本使用

```bash
cd /home/shiptux/git/gitee/compass-ci/sbin

# 1. 预览模式（不实际修改）
python3 reset_verification_status.py --dry-run --limit 10

# 2. 重置 200 个已验证任务
python3 reset_verification_status.py --limit 200

# 3. 重置所有已验证任务（谨慎使用）
python3 reset_verification_status.py --all --from-status verified

# 4. 重置所有成功的任务（无论验证状态）
python3 reset_verification_status.py --all --from-status all_success
```

### 4.2 重置后的状态

```json
{
  "bisect_status": "pending_verification",
  "j": {
    // 保留的原始信息
    "original_verification_status": "verified",
    "original_validation_status": "completed",
    "original_introduced_errids": [...],
    "reset_at": 1760393530,
    "reset_reason": "Code update - revalidation required",

    // 新的验证状态
    "verification_status": "pending",
    "validation_status": null,
    "verification_reset": true
  }
}
```

---

## 五、监控和调试

### 5.1 查看配置生效情况

```bash
# 检查进程的环境变量
ps aux | grep bisect
cat /proc/<PID>/environ | tr '\0' '\n' | grep VERIFICATION
```

### 5.2 监控验证进度

```sql
-- 查看待验证任务数量
SELECT COUNT(*) FROM bisect WHERE bisect_status = 'pending_verification';

-- 查看验证中的任务
SELECT COUNT(*) FROM bisect WHERE j.validation_status = 'validating';

-- 查看已验证任务
SELECT COUNT(*) FROM bisect WHERE j.verification_status = 'verified';
```

### 5.3 性能指标

**关键指标：**
- 验证吞吐量：每分钟完成的验证任务数
- 作业完成率：提交的作业中成功完成的比例
- 平均验证时长：从提交到完成的平均时间

---

## 六、故障排查

### 6.1 Producer 没有生成报告

**检查 producer 是否运行：**
```bash
# 查看最新的运行时间
cat /srv/result/bisect/producer_stats/producer_latest.txt

# 查看今天是否有报告
TODAY=$(date +%Y-%m-%d)
ls /srv/result/bisect/producer_stats/$TODAY/
```

**可能原因：**
1. Producer 被禁用：检查 `BISECT_PRODUCER_ENABLED` 环境变量
2. Producer 运行失败：查看系统日志

### 6.2 验证速度没有提升

**可能原因：**
1. 环境变量未生效
2. 作业提交限流
3. 测试资源不足

**检查方法：**
```bash
# 检查进程的环境变量
ps aux | grep bisect
cat /proc/<PID>/environ | tr '\0' '\n' | grep VERIFICATION
```

### 6.3 内存使用过高

**解决方案：**
降低批量大小
```bash
export VERIFICATION_BATCH_SIZE=100
export PARALLEL_VERIFICATION_JOBS=50
```

---

## 七、高级查询示例

### 7.1 分析错误 ID 趋势

```bash
#!/bin/bash
# 统计最近 7 天筛选成功的错误类型变化

echo "日期,筛选成功错误类型数,被过滤错误类型数"
for i in {6..0}; do
  DATE=$(date -d "$i days ago" +%Y%m%d)
  FILTERED=$(ls /srv/result/bisect/logs/analysis/filtered_jobs_${DATE}_*.json 2>/dev/null | head -1)
  UNFILTERED=$(ls /srv/result/bisect/logs/analysis/unfiltered_jobs_${DATE}_*.json 2>/dev/null | head -1)

  if [ -n "$FILTERED" ]; then
    F_COUNT=$(jq 'length' "$FILTERED")
    U_COUNT=$(jq 'length' "$UNFILTERED")
    echo "$(date -d "$i days ago" +%Y-%m-%d),$F_COUNT,$U_COUNT"
  fi
done
```

### 7.2 查找特定仓库的任务

```bash
# 查找 linux 仓库相关的所有筛选成功的错误
ls -t /srv/result/bisect/logs/analysis/filtered_jobs_*.json | head -1 | \
  xargs jq -r 'to_entries[] | select(.value.by_repository | keys[] | contains("linux")) | "\(.key): \(.value.total_tasks) 个任务"'
```

### 7.3 导出报告到 CSV

```bash
# 导出筛选成功的错误到 CSV
ls -t /srv/result/bisect/logs/analysis/filtered_jobs_*.json | head -1 | \
  xargs jq -r '["error_id","total_tasks","priority","category"],
               (to_entries[] | [.key, .value.total_tasks, .value.priority, .value.category]) | @csv' > filtered_errors.csv
```

---

## 八、文件清理建议

### 8.1 清理策略

**建议保留时间：**
- Producer 统计报告：保留 30 天
- Error ID 筛选分析：保留 14 天
- producer_latest.txt：始终保留

### 8.2 清理脚本示例

```bash
#!/bin/bash
# 清理超过 30 天的 producer 统计报告

STATS_DIR="/srv/result/bisect/producer_stats"
ANALYSIS_DIR="/srv/result/bisect/logs/analysis"

# 清理 30 天前的 producer 统计
find "$STATS_DIR" -maxdepth 1 -type d -name "20*" -mtime +30 -exec rm -rf {} \;

# 清理 14 天前的筛选分析文件
find "$ANALYSIS_DIR" -type f -name "*.json" -mtime +14 -delete
find "$ANALYSIS_DIR" -type f -name "*.txt" -mtime +14 -delete

echo "清理完成"
```

---

## 九、快速参考 (Repo Manager)

### 9.1 立即可用的命令

**运行基准测试**

```bash
# 方法1: 快速测试（2-3分钟，使用小型测试仓库）
cd /home/shiptux/git/gitee/compass-ci/container/bisect/scripts
./benchmark_clones_quick.py

# 方法2: 准确测试（10-20分钟，使用真实仓库）
./benchmark_clones_quick.py --repo https://gitee.com/openeuler/kernel.git --clones 10

# 方法3: Bash版本
./benchmark_concurrent_clones.sh
```

**应用配置**

根据基准测试结果更新配置：

```bash
# 环境变量方式（推荐）
export BISECT_MAX_CONCURRENT_CLONES=8

# 或编辑配置文件
vim /home/shiptux/git/gitee/compass-ci/container/bisect/lib/config.py
# 修改第53行: BISECT_MAX_CONCURRENT_CLONES = 8
```

### 9.2 关键改进对比

| 指标 | 重构前 | 重构后 | 改善 |
|------|--------|--------|------|
| 代码行数 | 1707 | 555 | -67% |
| 锁数量 | 8 | 3 | -62% |
| 状态管理 | 复杂 | 无状态 | ✓ |
| 任务隔离 | 部分 | 完全 | ✓ |
| 空间优化 | 池复用 | --reference | ✓ |

### 9.3 故障排查

**问题：克隆超时**
```bash
# 检查网络
ping gitee.com

# 增加超时（config.py:57-59）
GIT_CLONE_PRISTINE_TIMEOUT = 7200  # 2小时
GIT_CLONE_WORKSPACE_TIMEOUT = 7200
```

**问题：tmpfs满**
```bash
# 检查使用情况
df -h /tmp

# 降低并发
export BISECT_MAX_CONCURRENT_CLONES=2

# 或清理旧workspace
# (自动清理：每6小时清理>14天的目录)
```

**问题：吞吐量低**
```bash
# 增加并发（需要基准测试验证）
export BISECT_MAX_CONCURRENT_CLONES=12

# 检查系统负载
top
free -h
iostat
```

---

## 十、相关文档

- [设计文档](./DESIGN.md) - 系统架构和设计原理
- [测试文档](./TESTING.md) - 测试指南和覆盖率报告
- [API 文档](./API_DOCUMENTATION.md) - API 接口说明

---

**最后更新**: 2024-10-27
**维护者**: Bisect Team
