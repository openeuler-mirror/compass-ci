# Bisect 系统技术总结文档

## 1. 项目概述

### 1.1 目标

Bisect 系统是一个自动化 git bisect 工具，用于定位 Linux 内核等项目中引入 bug 的第一个坏提交 (First Bad Commit)。

### 1.2 设计目标

1. **准确性**: 准确找到导致问题的第一个提交，排除环境噪声干扰
2. **效率**: 通过二分查找最小化测试次数
3. **鲁棒性**: 处理编译失败、测试超时、环境问题等异常
4. **自动化**: 减少人工干预
5. **可复用性**: 相似问题复用已有结果

### 1.3 支持的 Bisect 类型

| 类型 | 描述 | 判定方式 |
|------|------|----------|
| 构建 (Build) | 编译错误 | error_id 是否出现 |
| 功能 (Functional) | LTP 等测试失败 | 测试用例是否通过 |
| 性能 (Performance) | 指标回归 | 数值是否超出 range |

---

## 2. 系统架构

### 2.1 整体流程

```
+-----------------+          +------------+           +-------------------------+
| upstream update | -+-----> | benchmark  | ------+-> |         jobs db         |
+-----------------+  |       +------------+       |   +-------------------------+
                     |                            |     |
                     |       +------------+       |     | bad_job
                     +-----> |   build    | ------+     v
                     |       +------------+       |   +-------------------------+
                     |                            |   |  bisect-task producer   |
                     |       +------------+       |   +-------------------------+
                     +-----> | functional | ------+     |
                             +------------+             v
                                                      +-------------------------+
                                                      |        bisect db        |
                                                      +-------------------------+
                                                        |
                                                        | task wait to be bisect
                                                        v
                                                      +-------------------------+
                                                      |   bisect-task consumer  |
                                                      +-------------------------+
                                                        |           ^
                                                        v           | result
                                                      +-------------------------+
                                                      |        bisect-py        |
                                                      +-------------------------+
```

### 2.2 核心组件

| 组件 | 职责 | 位置 |
|------|------|------|
| Producer | 扫描 jobs 表，发现失败任务，创建 bisect 任务 | `core/bisect_producer.py` |
| Consumer | 执行完整的 bisect 流程 | `core/bisect_consumer.py` |
| TaskProcessor | 任务聚类、调度、状态管理 | `core/task_processor.py` |
| VerificationConsumer | 验证复用结果 | `core/verification_consumer.py` |
| CommitTimeService | 检查 commit 年龄和版本 | `services/commit_time_service/` |
| RepoManager | 仓库池化管理 | `lib/repo_manager.py` |
| ErridIntelligence | error_id 智能筛选 | `lib/errid_intelligence.py` |

---

## 3. 核心算法与难点解决

### 3.1 任务优先级调度

**难点**: bisect 任务量大，资源有限，需要智能调度

**解决方案**: 权重分级 + 动态调整 + 防饿死

```python
PRIORITY_WEIGHTS = {
    "suite": 2,      # 核心测试集 +2
    "repo": 1,       # 高优先级仓库 +1
    "error_id": 3    # 关键错误类型 +3
}

# 动态调整：近期高频错误自动提升权重
# 防饿死：长期未处理任务逐步提升优先级
time_decay = (current_time - task.create_time).days // 7
priority_level += min(time_decay, max_priority_boost)
```

### 3.2 任务去重机制

**难点**: 同一问题可能触发多个 errid，重复 bisect 浪费资源

**解决方案**: 两阶段去重

```
阶段1 - 创建任务时：
  fingerprint = hash(error_id + suite + repo)

阶段2 - 运行完成后：
  去重键 = project + error_id + first_bad_commit
```

### 3.3 Good Commit 查找

**难点**: 找不到有效的 good commit 导致 bisect 失败

**解决方案**: 多策略回退

```python
# 策略1：数据库查找历史 tags
find_good_commit_by_db()

# 策略2：时间回溯 [1, 3, 10, 30] 天前的 commit
find_good_commit_by_job()

# 策略3：git-base-rc-tag.sh 找最近的 rc tag
# 如果 rc 也是 bad，继续往前找，最多 500 个
```

### 3.4 性能 Bisect 判定

**难点**: 性能指标是浮点数，非简单的 0/1 判定

**解决方案**: 基于 range 的判定

```python
# 获取基准 range
submit nearest_tag 3 times → get range (mean ± std)

# Bisect step 判定
if metric_value out of range in same direction as good_commit:
    return GOOD
elif build_error or run_error:
    return SKIP
else:
    return BAD

# 变化阈值：5% 以上幅度作为显著变化
```

### 3.5 Error ID 智能筛选

**难点**: 一个 job 可能有大量 errid，需要筛选出最适合 bisect 的

**解决方案**: 白名单 + 黑名单 + 优先级评分

```yaml
# 黑名单（环境错误，不适合 bisect）
- curl.*error
- File.already.exists
- ==>WARNING:Skipping

# 白名单（高价值错误）
- kernel.*panic
- fortify-string.*overflow

# 优先级评分
has_file_path: +30
critical_error: +40
code_related: +20
```

### 3.6 任务聚类与签名提取

**难点**: 同一 commit 引入的错误表现为多个不同 errid

**解决方案**: 粗粒度签名聚类

```python
# 提取签名：file_path + error_type
"nbl_core/nbl_service.c::error"

# 特殊处理：CONFIG 依赖错误保留具体名称
"makepkg::unmet-deps::CAN_DEV"  # 不同 CONFIG 独立测试
```

### 3.7 Commit 年龄/版本过滤

**难点**: 旧分支（如 v4.9）的 commit 即使日期新也不应 bisect

**解决方案**: 批量检查 + 版本比较

```python
# 批量检查 commit (1次网络调用替代N次)
1. 检查 commit 年龄 > 365 天 → 过滤
2. 检查 base_tag 版本 < 5.10 → 过滤

# git describe --tags --abbrev=0 获取最近祖先 tag
# 解析版本号比较: (6, 6, 0) vs (5, 10, 0)
```

### 3.8 仓库池化管理

**难点**: 频繁克隆大仓库耗时且占用空间

**解决方案**: Pristine + Reference Clone + 池化复用

```
/bisect_repos/
├── pristine/           # Bare 镜像仓库
│   └── linux/          # 共享对象库
├── pool/               # 可用仓库池
│   ├── linux-1/        # 实例 1
│   └── linux-2/        # 实例 2
└── workspaces/         # 正在使用的工作区
    └── task-123/
        └── linux/      # mv 自 pool
```

**性能对比**:
| 操作 | 旧方案 | 新方案 | 提升 |
|------|--------|--------|------|
| 首次获取 | ~20分钟 | ~20分钟 | - |
| 后续获取 | ~20分钟 | ~100ms | **12000x** |

---

## 4. 任务状态机

```
                    +--------+
                    |  wait  |
                    +--------+
                        |
           +------------+------------+
           |                         |
           v                         v
    +------------+           +------------------+
    | processing |           | pending_verif    |
    +------------+           +------------------+
           |                         |
    +------+------+           +------+------+
    |      |      |           |             |
    v      v      v           v             v
+-------+ +------+ +------+ +-------+  +---------+
|success| |failed| | skip | |success|  |  wait   |
+-------+ +------+ +------+ +-------+  |(回退bisect)
                                       +---------+
```

### 状态说明

| 状态 | 描述 |
|------|------|
| wait | 等待处理 |
| processing | 正在执行 bisect |
| pending_verification | 等待边界验证（复用场景） |
| verifying | 正在验证复用结果 |
| success | bisect 成功，找到 first_bad_commit |
| failed | bisect 失败 |

---

## 5. 数据库设计

### 5.1 Bisect 表核心字段

```sql
CREATE TABLE bisect (
  id BIGINT PRIMARY KEY,
  bad_job_id VARCHAR(32),
  error_id TEXT,
  git_url VARCHAR(512),
  bisect_status ENUM('wait','processing','success','failed','verifying'),
  first_bad_commit VARCHAR(64),
  category VARCHAR(32),           -- build/function/benchmark
  priority_level INT DEFAULT 0,
  retry_count INT DEFAULT 0,
  bisect_failed_reason TEXT,
  submit_time INT,
  updated_at INT,
  j JSON                          -- 扩展字段
);
```

### 5.2 j 字段结构

```json
{
  "good_commit": "abc123...",
  "related_task_id": "123456",
  "error_signature": "file.c::error",
  "skip_clustering": false,
  "marking_attempts": 0,
  "verification_status": "pending"
}
```

---

## 6. 配置参数

### 6.1 核心配置 (`lib/config.py`)

| 参数 | 默认值 | 说明 |
|------|--------|------|
| BISECT_THREADS | 32 | 并发 bisect 线程数 |
| BISECT_MAX_CONCURRENT_CLONES | 4 | 并发 clone 数 |
| REPO_POOL_MAX_INSTANCES | 150 | 每个仓库最大实例数 |
| BISECT_MIN_KERNEL_VERSION | 5.10 | 最小内核版本过滤 |
| BISECT_MAX_COMMIT_AGE_DAYS | 365 | 最大 commit 年龄 |
| BISECT_PRODUCER_QUERY_HOURS | 25 | 查询时间范围 |

### 6.2 环境变量

```bash
export BISECT_THREADS=32
export BISECT_MIN_KERNEL_VERSION=5.10
export BISECT_MAX_COMMIT_AGE_DAYS=365
export REPO_POOL_MAX_INSTANCES=150
```

---

## 7. 关键指标

| 指标 | 定义 | 目标 |
|------|------|------|
| 成功率 | bisect_status=success 的比例 | >=95% (构建) |
| 漏检率 | 失败 jobs 无 errid + errid 未能 bisect | <=10% |
| 重复率 | 相同 first_bad_commit 的任务比例 | <=2% |
| 时效 | 从发现到 bisect 完成 | <=1天 |

---

## 8. 主要 Bug 修复历史

| 问题 | 原因 | 解决 |
|------|------|------|
| 标签同时为好和坏 | rc tag 也是 bad | 继续往前找更早的 tag |
| errid 单引号丢失 | 数据库存储问题 | 模糊匹配 |
| 找不到 good commit | euler 分支宽度小 | 增加大粒度搜索 |
| 进程泄漏 | 线程池 git 冲突 | 改用进程池 |
| 硬盘跑满 | git 目录未清理 | 定期清理 + 复用 |
| 聚类标记失败 | 达到重试上限直接 fail | 改为跳过聚类，走独立 bisect |
| 内存同步问题 | 清理脏数据后内存未更新 | 同步更新内存中的 task 对象 |

---

## 9. Producer 5 阶段流水线

```
Phase 0: 收集 job 基本信息
    ↓
Phase 1: 批量检查 commit 年龄/版本 (1次网络调用)
    ↓
Phase 2: 处理 error_ids (智能筛选)
    ↓
Phase 3: 批量去重检查
    ↓
Phase 4: 批量创建任务
```

---

## 10. API 接口

### 10.1 任务管理

```bash
# 创建任务
POST /api/bisect/tasks
{
  "bad_job_id": "25081717025771200",
  "error_id": "stderr.eid.xxx"
}

# 查询任务
GET /api/bisect/tasks?status=wait&limit=100

# 更新任务状态
PUT /api/bisect/tasks/{id}
{
  "bisect_status": "success",
  "first_bad_commit": "abc123..."
}
```

### 10.2 Commit 时间服务

```bash
# 检查 commit 年龄
GET /api/v1/commit/check?repo=xxx&commit=xxx&max_age_days=365

# 检查分支版本
GET /api/v1/commit/branch_check?repo=xxx&commit=xxx&min_version=5.10

# 批量检查
POST /api/v1/commit/batch_check
{
  "items": [...],
  "max_age_days": 365,
  "min_kernel_version": "5.10"
}
```

---

## 11. 目录结构

```
container/bisect/
├── app/                    # Flask API 应用
│   ├── controllers.py      # 业务控制器
│   └── routes.py           # 路由定义
├── core/                   # 核心业务逻辑
│   ├── bisect_producer.py  # 任务生产者
│   ├── bisect_consumer.py  # 任务消费者
│   └── task_processor.py   # 任务处理器
├── lib/                    # 公共库
│   ├── config.py           # 配置管理
│   ├── repo_manager.py     # 仓库管理
│   ├── errid_intelligence.py # error_id 智能筛选
│   └── bisect_utils.py     # 工具函数
├── services/               # 微服务
│   └── commit_time_service/  # commit 时间服务
├── validators/             # 验证器
│   ├── head_validator.py   # HEAD 验证
│   └── success_task_validator.py # 成功任务验证
├── config/                 # 配置文件
│   └── errid_filters.yaml  # error_id 过滤规则
├── docs/                   # 文档
└── scripts/                # 脚本工具
```

---

## 12. 参考文档

- [ALGORITHM.md](./ALGORITHM.md) - 详细算法设计
- [DESIGN.md](./DESIGN.md) - 系统设计文档
- [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) - API 文档
- [DATA_BASE.md](./DATA_BASE.md) - 数据库设计
- [USER_GUIDE.md](./USER_GUIDE.md) - 用户指南
- [TESTING.md](./TESTING.md) - 测试文档

---

*文档版本: 2025-12-26*
*基于开发日志 2025.02 - 2025.12 整理*
