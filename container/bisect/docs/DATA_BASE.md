# Bisect 系统数据库文档

## 概述

本文档详细说明 Bisect 系统使用的 ManticoreSearch 数据库表结构、字段定义和数据关系。系统包含三个核心表：`bisect`、`jobs` 和 `regression`。

---

## 一、数据库表结构

### 1.1 Bisect 表 (`bisect`)

**用途**: 存储所有 bisect 任务的状态、进度和结果信息

```sql
CREATE TABLE bisect(
    id                      bigint,           -- 任务唯一ID
    bad_job_id              string,           -- 触发bisect的作业ID
    error_id                string,           -- 错误ID（错误类型任务）
    bisect_status           string,           -- 任务状态: wait/processing/success/failed/pending_verification
    bisect_metric          string,           -- 性能指标（性能类型任务）
    direction               string,           -- 性能方向: worse/better（仅性能任务）
    category                string,           -- 任务分类: build/function/benchmark
    project                 string,           -- 项目名称
    git_url                 string,           -- Git仓库URL
    first_bad_commit        string,           -- 找到的第一个坏提交
    first_bad_id            string,           -- 第一个坏提交的ID
    first_result_root       string,           -- 第一个结果根目录
    bisect_result_root      string,           -- bisect结果根目录
    submit_time             BIGINT,           -- 任务提交时间戳
    start_time              BIGINT,           -- 任务开始时间戳
    end_time                BIGINT,           -- 任务结束时间戳
    priority_level          INT,              -- 优先级级别
    timeout                 INT,              -- 超时时间（秒）
    retry_count             INT,              -- 重试次数
    last_error              string,           -- 最后错误信息
    updated_at              BIGINT,           -- 最后更新时间戳
    j                       json              -- JSON扩展字段，存储验证、优化等元数据
) charset_table='U+0021..U+007E';
```

#### 关键字段说明

**任务状态 (`bisect_status`)**:
- `wait`: 等待处理
- `processing`: 正在处理中
- `success`: 成功完成
- `failed`: 处理失败
- `pending_verification`: 等待验证

**任务分类 (`category`)**:
- `build`: 构建任务（suite为makepkg/pkgbuild）
- `function`: 功能测试任务
- `benchmark`: 性能测试任务（有bisect_metric）

**性能方向 (`direction`)**:
- `worse`: 性能变差（数值增大表示变差）
- `better`: 性能变好（数值减小表示变好）
- 空值: 错误类型任务不使用此字段

**JSON扩展字段 (`j`)**:
```json
{
  // 用户输入的参数
  "good_commit": "abc123...",  // 可选，用户指定的已知好提交

  // 验证相关
  "verification_status": "verified|verification_failed|pending",
  "verified_at": 1697123456,
  "parent_job_id": "z9.123456",
  "bad_job_id": "z9.234567",
  "introduced_errids": ["stderr.kernel_panic", "stderr.oops"],

  // HEAD检查相关
  "head_check_status": "regressed|fixed|ok",
  "head_check_at": 1697234567,
  "head_check_commit": "abc123...",
  "head_check_job_id": "z9.345678",
  "regressed_errids": ["stderr.kernel_panic"],

  // 任务优化相关
  "optimized": true,
  "optimization_strategy": "reuse|verify|priority",
  "optimization_source_task": 12345,
  "optimized_at": 1697345678
}
```

### 1.2 Jobs 表 (`jobs`)

**用途**: 存储所有测试作业的原始数据，为 bisect 提供基础数据源

```sql
CREATE TABLE jobs(
    id              bigint,           -- 作业唯一ID
    suite           string,           -- 测试套件名称
    category        string,           -- 作业分类
    my_account      string,           -- 账户信息
    testbox         string,           -- 测试环境
    arch            string,           -- 架构
    osv             string,           -- 操作系统版本
    submit_time     bigint,           -- 提交时间戳
    boot_time       bigint,           -- 启动时间戳
    running_time    bigint,           -- 运行时间戳
    finish_time     bigint,           -- 完成时间戳
    boot_seconds    int,              -- 启动耗时（秒）
    run_seconds     int,              -- 运行耗时（秒）
    istage          int,              -- 阶段标识
    ihealth         int,              -- 健康状态
    idata_readiness int,              -- 数据就绪状态
    j               json,             -- JSON扩展字段
    errid           text,             -- 错误ID列表
    full_text_kv    text              -- 完整文本键值对
) engine='columnar' charset_table='U+0021..U+007E';
```

#### 关键字段说明

**健康状态 (`ihealth`)**:
- 用于标识作业是否失败，bisect 生产者通过此字段发现失败作业

**错误ID (`errid`)**:
- 文本字段，存储作业产生的所有错误ID，用逗号分隔
- bisect 生产者从中提取有价值的错误ID创建任务

### 1.3 Regression 表 (`regression`)

**用途**: 存储回归分析结果和统计信息

```sql
CREATE TABLE regression(
    id              bigint,           -- 记录唯一ID
    record_type     string,           -- 记录类型: errid/metric
    errid           string,           -- 错误ID
    first_seen      bigint,           -- 首次出现时间戳
    last_seen       bigint,           -- 最后出现时间戳
    submit_time     bigint,           -- 提交时间戳
    metric_name     string,           -- 指标名称
    direction       string,           -- 方向: worse/better
    status          string,           -- 状态
    related_job     string,           -- 相关作业ID
    related_commit  string,           -- 相关提交
    j               json              -- JSON扩展字段
) engine='columnar' charset_table='U+0021..U+007E';
```

#### 关键字段说明

**记录类型 (`record_type`)**:
- `errid`: 错误类型回归记录
- `metric`: 性能指标回归记录

**JSON扩展字段 (`j`)**:
- 存储回归分析相关的扩展信息
- 如重复次数、影响范围等统计信息

---

## 二、数据关系与工作流

### 2.1 表间关系

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     Jobs 表     │    │    Bisect 表    │    │  Regression 表  │
│                 │    │                 │    │                 │
│ • 原始作业数据  │◄───┤ • bisect任务    │◄───┤ • 回归统计     │
│ • 错误ID列表    │    │ • 验证结果      │    │ • 重复分析      │
│ • 性能指标      │    │ • 优化标记      │    │ • 趋势分析      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │   Verified Task │
                        │      System     │
                        │                 │
                        │ • 边界验证      │
                        │ • HEAD检查      │
                        │ • 结果复用      │
                        └─────────────────┘
```

### 2.2 数据流转流程

1. **任务发现**: 生产者从 `jobs` 表发现失败作业，提取错误ID
2. **任务创建**: 在 `bisect` 表创建新任务，状态为 `wait`
3. **任务处理**: Consumer 处理任务，更新状态为 `processing`
4. **结果验证**: 成功任务进入验证流程，更新 `j` 字段验证信息
5. **回归记录**: 验证成功的任务写入 `regression` 表
6. **结果复用**: 基于已验证任务优化其他等待任务

---

## 三、任务类型说明

### 3.1 错误类型 Bisect

**特征**: 基于错误ID进行二分查找，定位引入错误的第一个提交

```json
{
  "bad_job_id": "25102209094235200",
  "error_id": "stderr.compilation_error:undefined_reference",
  "direction": "",  // 不使用方向字段
  "category": "build"  // 自动分类为构建任务
}
```

### 3.2 性能类型 Bisect

**特征**: 基于性能指标进行二分查找，定位性能变化的第一个提交

```json
{
  "bad_job_id": "25102209094235200",  // 可能是回归也可能是提升
  "bisect_metrics": "boot_time",
  "direction": "worse",  // worse=性能回归, better=性能提升
  "category": "benchmark"  // 自动分类为性能测试
}
```

### 3.3 方向判断逻辑

性能 bisect 需要根据实际数值自动判断和验证方向：

```python
# 自动判断示例
if bad_commit_value > good_commit_value:
    actual_direction = "worse"  # 数值增大=性能变差
else:
    actual_direction = "better" # 数值减小=性能变好

# 验证用户输入的direction是否与实际一致
if actual_direction != user_direction:
    logger.warning("方向不匹配，需要检查数据")
```

---

## 四、常用 SQL 查询

### 4.1 统计分析查询

#### 按类别统计成功的 bisect 中相同 commit 的重复率
```sql
-- 按类别统计成功的 bisect 中相同 commit 的重复率
SELECT
    category,
    first_bad_commit,
    COUNT(*) as commit_count,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY category) as percentage
FROM bisect
WHERE bisect_status = 'success' AND first_bad_commit != ''
GROUP BY category, first_bad_commit
ORDER BY category, commit_count DESC;
```

#### 性能 bisect 的方向分析
```sql
-- 性能任务的方向统计
SELECT
    direction,
    COUNT(*) as task_count,
    SUM(CASE WHEN bisect_status = 'success' THEN 1 ELSE 0 END) as success_count,
    ROUND(SUM(CASE WHEN bisect_status = 'success' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as success_rate
FROM bisect
WHERE category = 'benchmark' AND direction != ''
GROUP BY direction
ORDER BY task_count DESC;
```

#### 各类别的 bisect 成功率统计
```sql
-- 各类别的 bisect 成功率统计
SELECT
    category,
    COUNT(*) as total_tasks,
    SUM(CASE WHEN bisect_status = 'success' THEN 1 ELSE 0 END) as success_count,
    SUM(CASE WHEN bisect_status = 'failed' THEN 1 ELSE 0 END) as failed_count,
    SUM(CASE WHEN bisect_status = 'success' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as success_rate
FROM bisect
GROUP BY category
ORDER BY success_rate DESC;
```

### 4.2 验证状态查询

#### 查询已验证任务统计
```sql
-- 验证状态分布统计
SELECT
    j.verification_status,
    COUNT(*) as count
FROM bisect
WHERE bisect_status = 'success'
GROUP BY j.verification_status;
```

#### 查询 HEAD 检查状态
```sql
-- HEAD 检查状态统计
SELECT
    j.head_check_status,
    COUNT(*) as count
FROM bisect
WHERE j.verification_status = 'verified'
GROUP BY j.head_check_status;
```

### 4.3 任务队列查询

#### 查询等待处理的任务
```sql
-- 按优先级查询等待任务
SELECT
    category,
    priority_level,
    COUNT(*) as task_count
FROM bisect
WHERE bisect_status = 'wait'
GROUP BY category, priority_level
ORDER BY priority_level DESC, category;
```

#### 查询验证中的任务
```sql
-- 查询待验证任务
SELECT
    category,
    COUNT(*) as task_count
FROM bisect
WHERE bisect_status = 'pending_verification'
GROUP BY category
ORDER BY task_count DESC;
```

---

## 五、设计优势与最佳实践

### 5.1 设计优势

使用 bisect 表进行统计分析比 regression 表更准确，因为：

1. **完整性**: bisect 表包含所有任务（成功/失败/处理中），regression 表只有成功的
2. **实时性**: bisect 表实时更新状态，能反映当前处理情况
3. **准确性**: 基于完整数据的统计更能反映真实的重复率和成功率
4. **方向信息**: bisect 表记录执行时的方向信息，更准确反映任务意图

### 5.2 最佳实践

1. **分类统计**: 重复率计算应该按 category 和 direction 分别统计，不同类型和方向的任务不应混合分析
2. **数据清理**: `first_bad_commit` 为空的成功任务可能是 bisect 过程中的异常情况，需要排除统计
3. **索引优化**: 建议为常用查询字段创建索引：
   - `bisect_status`, `category`, `direction`
   - `j.verification_status`, `j.head_check_status`
   - `submit_time`, `updated_at`

### 5.3 性能优化

#### 批量查询优化
避免在生产者中对每个错误ID执行单独查询：

```sql
-- 批量查询示例（推荐）
SELECT * FROM bisect
WHERE bad_job_id = '25102209094235200'
AND error_id IN ('errid1', 'errid2', 'errid3', ...);
```

#### 查询缓存
对于频繁查询的(bad_job_id, error_id)组合，建议使用查询缓存机制减少数据库负载。

---

## 六、总结

### 6.1 核心表结构总结

| 表名 | 用途 | 关键字段 | 引擎类型 |
|------|------|----------|----------|
| **bisect** | 存储bisect任务状态和结果 | `bisect_status`, `category`, `direction`, `j` | 默认引擎 |
| **jobs** | 存储原始作业数据 | `errid`, `ihealth`, `suite` | columnar |
| **regression** | 存储回归分析结果 | `record_type`, `errid`, `direction` | columnar |

### 6.2 数据设计原则

1. **向后兼容**: 所有新功能通过 JSON `j` 字段扩展，无需修改表结构
2. **性能优先**: 关键查询字段建立索引，支持批量查询优化
3. **数据完整**: bisect 表包含完整任务生命周期，支持准确统计分析
4. **灵活扩展**: JSON 字段设计支持系统功能的持续演进

### 6.3 使用建议

1. **统计分析**: 优先使用 bisect 表进行统计分析，数据更完整准确
2. **查询优化**: 使用批量查询和缓存机制提升性能
3. **监控指标**: 关注任务队列长度、验证成功率、重复率等关键指标
4. **数据维护**: 定期清理异常数据，保持数据质量

---

**最后更新**: 2024-10-27
**维护者**: Bisect Team

### 1.1 核心字段（无变化）

```sql
-- 这些字段在原有bisect系统中已存在，无需修改
id                  BIGINT        -- 任务ID
bad_job_id          TEXT          -- 出错的作业ID
error_id            TEXT          -- 错误ID
git_url             TEXT          -- Git仓库URL
bisect_status       TEXT          -- 任务状态: wait/processing/success/failed
first_bad_commit    TEXT          -- 找到的坏提交
priority_level      INT           -- 优先级
created_at          TIMESTAMP     -- 创建时间
updated_at          TIMESTAMP     -- 更新时间
start_time          TIMESTAMP     -- 开始时间
end_time            TIMESTAMP     -- 结束时间
```

### 1.2 扩展字段：JSON 'j' 字段

**关键设计原则**：所有新增元数据都存储在 `j` JSON字段中，无需修改表结构。

```json
{
  // ========== 验证相关字段 ==========
  "verification_status": "verified",           // 验证状态: verified/verification_failed/pending
  "verified_at": 1697123456,                   // 验证完成时间戳
  "verification_method": "success_task_validation",  // 验证方法
  "verification_failure_reason": "",           // 验证失败原因
  "retry_count": 0,                            // 重试次数

  // ========== 边界验证作业ID ==========
  "parent_job_id": "z9.123456",               // 父提交的测试作业ID
  "bad_job_id": "z9.234567",                  // bad commit的测试作业ID（候选提交）

  // ========== Errid Diff 结果 ==========
  "introduced_errids": [                       // 该commit引入的新错误
    "stderr.kernel_panic",
    "stderr.oops",
    "dmesg.warning"
  ],

  // ========== HEAD 检查相关 ==========
  "head_check_status": "regressed",           // HEAD状态: regressed/fixed/ok
  "head_check_at": 1697234567,                // HEAD检查时间戳
  "head_check_commit": "abc123...",           // 检查的HEAD commit
  "head_check_job_id": "z9.345678",           // HEAD测试作业ID
  "regressed_errids": [                        // 在HEAD上回归的errid
    "stderr.kernel_panic"
  ],

  // ========== 任务优化相关 ==========
  "optimized": true,                          // 是否被优化过
  "optimization_strategy": "reuse",           // 优化策略: reuse/verify/priority
  "optimization_source_task": 12345,          // 优化来源任务ID
  "optimized_at": 1697345678,                 // 优化时间戳
  "result_source": "optimized_reuse",         // 结果来源标记

  // ========== 其他元数据 ==========
  "expected_commit": "def456...",             // 预期的候选commit（用于快速验证）
  "related_task_id": 67890,                   // 关联任务ID
  "priority_reason": "similar_task_exists"    // 优先级调整原因
}
```

---

## 二、流程 1：全新 Bisect 任务的完整流程

### 2.1 流程图

```
┌─────────────┐
│ 新建任务    │  bisect_status='wait'
│  error_id   │  j = {}
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Bisect Consumer │  bisect_status='processing'
│  执行 git bisect│  j = {}
└──────┬──────────┘
       │
       ▼
┌──────────────────────┐
│ Bisect 成功          │  bisect_status='success'
│  找到 first_bad_commit│  j = {}
└──────┬───────────────┘
       │
       ▼
┌────────────────────────────┐
│ SuccessTaskValidator       │  bisect_status='success'
│  边界验证 (parent vs bad)  │  j = {
└──────┬─────────────────────┘    "verification_status": "verified",
       │                            "verified_at": timestamp,
       ▼                            "parent_job_id": "z9.xxx",
   ┌───────┐                       "bad_job_id": "z9.yyy",
   │验证成功│                       "introduced_errids": [...]
   └───┬───┘                     }
       │
       ▼
┌─────────────────────────┐
│ HeadValidator           │  bisect_status='success'
│  在最新HEAD提交测试     │  j = {
└──────┬──────────────────┘    ... (保留上面的字段) ...
       │                        "head_check_status": "regressed",
       ▼                        "head_check_at": timestamp,
   ┌────────┐                  "head_check_commit": "HEAD",
   │检测回归│                  "head_check_job_id": "z9.zzz",
   └───┬────┘                  "regressed_errids": [...]
       │                      }
       ▼
┌─────────────┐
│ 触发通知    │
│  告警/报告  │
└─────────────┘
```

### 2.2 数据状态变化详解

#### 阶段 1: 新建任务
```json
{
  "id": 12345,
  "bad_job_id": "z9.100001",
  "error_id": "stderr.kernel_panic",
  "git_url": "https://github.com/torvalds/linux.git",
  "bisect_status": "wait",
  "first_bad_commit": "",
  "j": {}
}
```

#### 阶段 2: Bisect 处理中
```json
{
  "bisect_status": "processing",
  "j": {}
}
```

#### 阶段 3: Bisect 成功
```json
{
  "bisect_status": "success",
  "first_bad_commit": "a1b2c3d4e5f6...",
  "start_time": 1697100000,
  "end_time": 1697102000,
  "j": {}
}
```

#### 阶段 4: 边界验证完成
```json
{
  "bisect_status": "success",
  "first_bad_commit": "a1b2c3d4e5f6...",
  "j": {
    "verification_status": "verified",
    "verified_at": 1697103000,
    "verification_method": "success_task_validation",
    "parent_job_id": "z9.200001",
    "bad_job_id": "z9.200002",
    "introduced_errids": [
      "stderr.kernel_panic",
      "stderr.oops",
      "dmesg.hardware_error"
    ]
  }
}
```

#### 阶段 5: HEAD 检查完成（检测到回归）
```json
{
  "bisect_status": "success",
  "first_bad_commit": "a1b2c3d4e5f6...",
  "j": {
    "verification_status": "verified",
    "verified_at": 1697103000,
    "verification_method": "success_task_validation",
    "parent_job_id": "z9.200001",
    "bad_job_id": "z9.200002",
    "introduced_errids": [
      "stderr.kernel_panic",
      "stderr.oops",
      "dmesg.hardware_error"
    ],
    "head_check_status": "regressed",
    "head_check_at": 1697200000,
    "head_check_commit": "fedcba987654...",
    "head_check_job_id": "z9.300001",
    "regressed_errids": [
      "stderr.kernel_panic"
    ]
  }
}
```

#### 阶段 5b: HEAD 检查完成（已修复）
```json
{
  "j": {
    ... (保留验证字段) ...
    "head_check_status": "fixed",
    "head_check_at": 1697200000,
    "head_check_commit": "fedcba987654...",
    "head_check_job_id": "z9.300001",
    "regressed_errids": []
  }
}
```

---

## 三、流程 2：数据库中已有的 Bisect 任务验证流程

### 3.1 流程图

```
┌───────────────────┐
│ 数据库已有任务    │  bisect_status='success'
│  有 first_bad_commit │  first_bad_commit 已存在
└────────┬──────────┘  j = {}
         │
         ▼
┌─────────────────────────────┐
│ SuccessTaskValidator 扫描   │
│  扫描未验证的成功任务       │  SQL: WHERE bisect_status='success'
└────────┬────────────────────┘       AND j.verification_status IS NULL
         │
         ▼
┌──────────────────────────┐
│ 获取 Git 仓库            │  使用 SharedRepoManager
│  克隆/更新仓库           │  repo_dir, job_dir
└────────┬─────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│ 执行边界验证                    │
│  1. 获取 parent commit          │  git rev-parse <commit>^1
│  2. 并行提交两个测试作业        │  parent_job 和 candidate_job
│  3. 等待作业完成                │  GitBisect._poll_job_stats
│  4. 检查边界条件                │  parent=good, candidate=bad
└────────┬────────────────────────┘
         │
         ▼
     ┌───────┐
     │验证成功│
     └───┬───┘
         │
         ▼
┌──────────────────────────┐
│ 计算 errid diff          │
│  parent_errids = job_stats.keys()
│  bad_errids = job_stats.keys()
│  introduced = bad - parent
└────────┬─────────────────┘
         │
         ▼
┌───────────────────────────┐
│ 更新数据库                │  j = {
│  标记为已验证             │    "verification_status": "verified",
└────────┬──────────────────┘    "verified_at": timestamp,
         │                        "introduced_errids": [...],
         ▼                        "parent_job_id": "...",
┌─────────────────────────┐      "bad_job_id": "..."
│ HeadValidator 扫描      │    }
│  扫描已验证任务         │
└────────┬────────────────┘  SQL: WHERE j.verification_status='verified'
         │                         AND j.head_check_at < threshold
         ▼
┌──────────────────────────┐
│ 获取 HEAD commit         │  git rev-parse HEAD
│  提交 HEAD 测试          │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ 检查回归                 │
│  比较 introduced_errids  │  head_errids ∩ introduced_errids
│  与 HEAD 作业的 errids   │
└────────┬─────────────────┘
         │
         ▼
     ┌──────┐
     │已修复│ or ┌───────┐
     └──────┘    │已回归│
                 └───┬───┘
                     │
                     ▼
              ┌──────────┐
              │ 触发通知 │
              └──────────┘
```

### 3.2 数据状态变化详解

#### 阶段 0: 数据库中的旧任务
```json
{
  "id": 67890,
  "bad_job_id": "z9.400001",
  "error_id": "stderr.test_error",
  "git_url": "https://github.com/test/repo.git",
  "bisect_status": "success",
  "first_bad_commit": "1a2b3c4d5e6f...",
  "start_time": 1690000000,
  "end_time": 1690002000,
  "j": {}  // 空的，没有验证信息
}
```

#### 阶段 1: SuccessTaskValidator 扫描并验证
```json
{
  "bisect_status": "success",
  "first_bad_commit": "1a2b3c4d5e6f...",
  "j": {
    "verification_status": "verified",
    "verified_at": 1697500000,
    "verification_method": "success_task_validation",
    "parent_job_id": "z9.500001",
    "bad_job_id": "z9.500002",
    "introduced_errids": [
      "stderr.test_error",
      "stderr.another_error"
    ]
  }
}
```

#### 阶段 2: HeadValidator 检查
```json
{
  "bisect_status": "success",
  "first_bad_commit": "1a2b3c4d5e6f...",
  "j": {
    "verification_status": "verified",
    "verified_at": 1697500000,
    "verification_method": "success_task_validation",
    "parent_job_id": "z9.500001",
    "bad_job_id": "z9.500002",
    "introduced_errids": [
      "stderr.test_error",
      "stderr.another_error"
    ],
    "head_check_status": "fixed",
    "head_check_at": 1697600000,
    "head_check_commit": "abcdef123456...",
    "head_check_job_id": "z9.600001",
    "regressed_errids": []
  }
}
```

---

## 四、流程 3：任务优化流程（使用已验证结果）

### 4.1 流程图

```
┌──────────────────┐
│ 新任务进入       │  bisect_status='wait'
│  error_id 匹配   │  error_id="stderr.test_error"
└────────┬─────────┘  j = {}
         │
         ▼
┌────────────────────────────┐
│ TaskOptimizer 扫描         │  SQL: WHERE bisect_status='wait'
│  查找待优化任务            │       AND error_id != ''
└────────┬───────────────────┘       AND j.optimized != true
         │
         ▼
┌──────────────────────────────┐
│ 查找匹配的已验证任务         │  SQL: WHERE j.verification_status='verified'
│  条件：                      │       AND git_url = '<same>'
│  1. 相同 git_url             │       AND j.introduced_errids 包含 error_id
│  2. introduced_errids 包含   │
│     新任务的 error_id        │
└────────┬─────────────────────┘
         │
         ▼
     ┌────────┐
     │找到匹配│
     └────┬───┘
          │
          ▼
   ┌──────────────────┐
   │ 应用优化策略     │
   └──────┬───────────┘
          │
          ├─────────────────────┬─────────────────────┬──────────────────
          │                     │                     │
          ▼                     ▼                     ▼
    ┌─────────┐          ┌─────────┐          ┌──────────┐
    │ reuse   │          │ verify  │          │ priority │
    │ 策略    │          │ 策略    │          │ 策略     │
    └────┬────┘          └────┬────┘          └────┬─────┘
         │                    │                     │
         ▼                    ▼                     ▼
    直接复用结果       设置为 pending_verification   降低优先级
    bisect_status=     bisect_status=              priority_level=1
      'success'         'pending_verification'     bisect_status='wait'
```

### 4.2 优化策略对应的数据变化

#### 策略 1: Reuse（直接复用）

**新任务初始状态**:
```json
{
  "id": 88888,
  "bad_job_id": "z9.700001",
  "error_id": "stderr.test_error",
  "git_url": "https://github.com/test/repo.git",
  "bisect_status": "wait",
  "j": {}
}
```

**匹配到的已验证任务**:
```json
{
  "id": 67890,
  "first_bad_commit": "1a2b3c4d5e6f...",
  "j": {
    "verification_status": "verified",
    "introduced_errids": ["stderr.test_error", ...]
  }
}
```

**优化后状态（reuse）**:
```json
{
  "id": 88888,
  "bisect_status": "success",
  "first_bad_commit": "1a2b3c4d5e6f...",  // 直接复用
  "start_time": 1697700000,
  "end_time": 1697700000,
  "j": {
    "optimized": true,
    "optimization_strategy": "reuse",
    "optimization_source_task": 67890,
    "optimized_at": 1697700000,
    "result_source": "optimized_reuse"
  }
}
```

#### 策略 2: Verify（快速验证）

**优化后状态（verify）**:
```json
{
  "id": 88888,
  "bisect_status": "pending_verification",
  "j": {
    "expected_commit": "1a2b3c4d5e6f...",  // 候选commit
    "related_task_id": 67890,
    "optimized": true,
    "optimization_strategy": "verify",
    "optimization_source_task": 67890,
    "optimized_at": 1697700000
  }
}
```

然后 VerificationConsumer 会处理这个任务进行边界验证。

#### 策略 3: Priority（降优先级）

**优化后状态（priority）**:
```json
{
  "id": 88888,
  "bisect_status": "wait",
  "priority_level": 1,  // 降低到最低优先级
  "j": {
    "optimized": true,
    "optimization_strategy": "priority",
    "optimization_source_task": 67890,
    "optimized_at": 1697700000,
    "priority_reason": "similar_task_exists"
  }
}
```

---

## 五、验证失败的处理

### 5.1 边界验证失败

当边界验证不通过时（parent 不是 good 或 candidate 不是 bad）：

```json
{
  "bisect_status": "success",  // 保持success
  "first_bad_commit": "1a2b3c4d5e6f...",
  "j": {
    "verification_status": "verification_failed",
    "verification_failed_at": 1697800000,
    "verification_failure_reason": "边界条件不满足: parent_status=bad, candidate_status=bad",
    "retry_count": 1
  }
}
```

**后续处理**：
- 可以被 Recovery Service 处理
- 重新进行完整 bisect
- 或者标记为需要人工审核

---

## 六、关键 SQL 查询

### 6.1 SuccessTaskValidator 查询

```sql
-- 扫描未验证的成功任务
SELECT * FROM bisect
WHERE bisect_status = 'success'
AND first_bad_commit != ''
AND (
    j.verification_status IS NULL
    OR j.verification_status != 'verified'
)
ORDER BY updated_at DESC
LIMIT 10;
```

### 6.2 HeadValidator 查询

```sql
-- 扫描需要HEAD检查的已验证任务
SELECT * FROM bisect
WHERE j.verification_status = 'verified'
AND j.introduced_errids IS NOT NULL
AND (
    j.head_check_at IS NULL
    OR j.head_check_at < (UNIX_TIMESTAMP() - 86400)  -- 24小时前
)
ORDER BY updated_at DESC
LIMIT 10;
```

### 6.3 TaskOptimizer 查询

```sql
-- 扫描待优化任务
SELECT * FROM bisect
WHERE bisect_status = 'wait'
AND error_id != ''
AND (j.optimized IS NULL OR j.optimized != true)
ORDER BY priority_level DESC, updated_at ASC
LIMIT 20;

-- 查找匹配的已验证任务
SELECT * FROM bisect
WHERE j.verification_status = 'verified'
AND git_url = '<target_git_url>'
AND j.introduced_errids IS NOT NULL
ORDER BY verified_at DESC
LIMIT 10;
```

---

## 七、数据完整性保证

### 7.1 必需字段检查

在各个阶段，确保以下字段存在：

**边界验证完成后**：
- `j.verification_status`
- `j.verified_at`
- `j.parent_job_id`
- `j.bad_job_id`
- `j.introduced_errids`

**HEAD检查完成后**：
- `j.head_check_status`
- `j.head_check_at`
- `j.head_check_commit`
- `j.head_check_job_id`
- `j.regressed_errids` (可为空列表)

**任务优化后**：
- `j.optimized`
- `j.optimization_strategy`
- `j.optimization_source_task`
- `j.optimized_at`

### 7.2 时间戳字段

所有时间戳使用 Unix timestamp (秒级)：
- `verified_at`
- `head_check_at`
- `optimized_at`

---

## 八、数据查询示例

### 8.1 查询所有已验证且在HEAD上回归的任务

```sql
SELECT
    id,
    error_id,
    first_bad_commit,
    j.head_check_status,
    j.regressed_errids
FROM bisect
WHERE j.verification_status = 'verified'
AND j.head_check_status = 'regressed'
ORDER BY j.head_check_at DESC;
```

### 8.2 查询所有优化成功的任务

```sql
SELECT
    id,
    error_id,
    bisect_status,
    j.optimization_strategy,
    j.optimization_source_task
FROM bisect
WHERE j.optimized = true
ORDER BY j.optimized_at DESC;
```

### 8.3 统计验证状态分布

```sql
SELECT
    j.verification_status,
    COUNT(*) as count
FROM bisect
WHERE bisect_status = 'success'
GROUP BY j.verification_status;
```

### 8.4 查询某个commit引入的所有错误

```sql
SELECT
    id,
    first_bad_commit,
    j.introduced_errids
FROM bisect
WHERE first_bad_commit = 'a1b2c3d4e5f6...'
AND j.verification_status = 'verified';
```

---

## 九、总结

### 9.1 表结构变化总结

| 变化类型 | 说明 |
|---------|------|
| **核心字段** | 无变化，完全兼容现有系统 |
| **JSON 'j' 字段** | 扩展元数据，向后兼容 |
| **索引需求** | 建议为 `j.verification_status`, `j.head_check_at`, `j.optimized` 创建索引 |

### 9.2 流程对比

| 流程 | 起始状态 | 关键步骤 | 最终状态 |
|-----|---------|---------|---------|
| **全新Bisect** | wait → processing → success | Git bisect → 边界验证 → HEAD检查 | success + verified + head_checked |
| **历史任务验证** | success (未验证) | 边界验证 → HEAD检查 | success + verified + head_checked |
| **任务优化** | wait (可优化) | 匹配已验证任务 → 应用策略 | success(reuse) / pending_verification(verify) / wait(priority) |

### 9.3 数据字段依赖关系

```
bisect_status='success' + first_bad_commit
    ↓
j.verification_status='verified' + j.introduced_errids
    ↓
j.head_check_status + j.regressed_errids
    ↓
用于优化其他任务
```

所有数据变化都在 JSON 'j' 字段中进行，确保：
- ✅ 向后兼容（旧任务 j={} 仍可正常工作）
- ✅ 无需修改表结构
- ✅ 灵活扩展新字段
- ✅ 数据完整性保证
