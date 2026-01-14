# 性能 Bisect 生产者设计方案

> 用于评审的设计文档

## 一、概述

### 1.1 目标

实现 `PerformanceBisectProducer`，自动从 kernel CI 性能测试结果中识别性能回归，并创建 bisect 任务定位引入回归的 commit。

### 1.2 分阶段实施

| 阶段 | 目标 | 状态 |
|------|------|------|
| 第一阶段 | 基于 kernel CI 的性能监控，使用 midpoint 算法识别可 bisect 的性能回归 | **本周完成** |
| 第二阶段 | 基于 KPI 框架的智能监控，支持更复杂的指标分析和阈值配置 | 规划中 |

---

## 二、系统架构

### 2.1 数据流

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Kernel CI Pipeline                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  daily_kernel_test.sh                                                        │
│       │                                                                      │
│       ├── 提交 baseline 任务 (stable tag: v6.17, 5.10.0-216.0.0)            │
│       └── 提交 current 任务 (RC/HEAD: v6.17-rc1, commit hash)               │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              jobs 表                                         │
│  存储: suite, testbox, commit, stats, submit_time                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    PerformanceBisectProducer (本次实现)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  Phase 1: 查询性能测试 jobs                                                  │
│  Phase 2: 按 (repo, branch, suite, testbox) 分组                            │
│  Phase 3: 识别 baseline/current 配对                                        │
│  Phase 4: 应用 midpoint 算法筛选可 bisect 的配对                            │
│  Phase 5: 创建 bisect 任务                                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              bisect 表                                       │
│  category='benchmark', bisect_metric, direction, mid_point                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           BisectConsumer                                     │
│  使用 performance_bisect.py + bisect_midpoint_step.py 执行二分              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 核心算法: Midpoint

```
              v1 (baseline)           v2 (current)
              ┌─────────┐             ┌─────────┐
samples:      │ 100     │             │ 150     │
              │ 102     │             │ 155     │
              │ 98      │             │ 148     │
              └─────────┘             └─────────┘
                 │                       │
              min=98                  min=148
              max=102                 max=155

判断条件: v1_max (102) < v2_min (148)  → 存在不重叠的性能差距

midpoint = (v1_max + v2_min) / 2 = (102 + 148) / 2 = 125

bisect 评估:
  - sample > 125 → BAD (性能变差)
  - sample ≤ 125 → GOOD (性能正常)
```

---

## 三、第一阶段实现 (本周)

### 3.1 文件修改清单

| 文件 | 修改类型 | 描述 |
|------|----------|------|
| `container/bisect/lib/config.py` | 修改 | 添加性能生产者配置项 |
| `container/bisect/config/performance_metrics.yaml` | 新增 | 指标配置文件 |
| `container/bisect/core/bisect_producer.py` | 修改 | 实现 PerformanceBisectProducer |

### 3.2 配置项

```python
# 启用/禁用性能生产者
PERFORMANCE_PRODUCER_ENABLED = true

# 查询时间范围 (小时)
PERFORMANCE_PRODUCER_QUERY_HOURS = 168  # 7天

# 生产者执行间隔 (天)
PERFORMANCE_PRODUCER_INTERVAL_DAYS = 7

# 最小性能变化百分比触发 bisect
PERFORMANCE_MIN_CHANGE_PERCENT = 5.0

# 最小样本数要求
PERFORMANCE_MIN_SAMPLES = 2

# 监控的测试套件
PERFORMANCE_SUITES = 'unixbench,lmbench,iozone,fio,stream,hackbench,netperf'
```

### 3.3 监控指标

配置文件 `performance_metrics.yaml` 定义了各套件的监控指标：

| Suite | 指标示例 | 方向 |
|-------|----------|------|
| unixbench | score, System_Call_Overhead, Process_Creation | +1 (越大越好) |
| lmbench | lat_ctx, lat_syscall, lat_pipe | -1 (越小越好) |
| fio | read_iops, write_iops, read_lat_mean | +1/-1 |
| iozone | sequential_read, sequential_write | +1 |
| stream | copy, scale, add, triad | +1 |

### 3.4 任务数据结构

```json
{
  "bad_job_id": "25112012334404900",
  "bisect_metric": "unixbench.score",
  "direction": "worse",
  "category": "benchmark",
  "git_url": "https://gitee.com/openeuler/kernel.git",
  "bisect_status": "wait",
  "j": {
    "good_commit": "v6.17",
    "mid_point": 125.0,
    "metric_direction": 1,
    "v1_samples": [100, 102, 98],
    "v2_samples": [150, 155, 148],
    "v1_range": [98, 102],
    "v2_range": [148, 155],
    "change_percent": 45.1,
    "baseline_commit": "v6.17",
    "current_commit": "abc123...",
    "suite": "unixbench",
    "source": "performance_producer"
  }
}
```

### 3.5 关键设计决策

| 决策 | 说明 |
|------|------|
| **Midpoint 算法** | 使用不重叠范围检测，避免噪声干扰，确保 bisect 有效性 |
| **Baseline 识别** | 通过 tag 模式匹配 (v6.17, 5.10.0-216.0.0)，自动区分稳定版和开发版 |
| **多指标监控** | 任一指标出现可 bisect 变化即触发，每个指标单独创建任务 |
| **去重机制** | LRU 缓存 + 数据库查询，避免重复任务 |
| **配置化** | 指标和阈值通过 YAML 配置，无需改代码 |

---

## 四、第二阶段扩展 (KPI 智能监控)

### 4.1 扩展方向

基于 `kpi-design-reference.md` 的设计模式：

```
┌─────────────────────────────────────────────────────────────────┐
│                      KPI 配置层                                  │
├─────────────────────┬───────────────────────────────────────────┤
│  全局规则配置        │  测试套件级配置                            │
│  (正则 + 权重)       │  (具体指标 + 基准值)                       │
└─────────────────────┴───────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      KPI 判断层                                  │
├─────────────────────┬───────────────────────────────────────────┤
│  宽松模式            │  严格模式                                  │
│  (属于测试即可)      │  (必须匹配规则)                            │
└─────────────────────┴───────────────────────────────────────────┘
```

### 4.2 计划增强功能

1. **KPI 规则引擎**
   - 支持正则表达式匹配指标
   - 支持语义化后缀自动判断方向 (`.LAT.`, `.RATE.`)
   - 支持 baseline 基准值配置

2. **智能阈值**
   - 按指标类型自动调整阈值
   - 支持历史数据统计分析

3. **告警分级**
   - 严格模式：只处理关键 KPI
   - 宽松模式：全面分析

4. **与 lkp-tests KPI 集成**
   - 复用 `etc/index-perf-all.yaml` 规则
   - 复用 `programs/*/meta.yaml` 定义

---

## 五、测试计划

### 5.1 单元测试

- `_is_baseline_commit()`: 测试各种 tag 格式识别
- `_check_performance_gap()`: 测试 midpoint 算法
- `_get_metric_direction()`: 测试方向判断

### 5.2 集成测试

- 查询 jobs 表并解析数据
- 创建 bisect 任务到数据库
- 验证任务结构正确性

### 5.3 端到端测试

- 手动触发生产者循环
- 验证任务进入 BisectConsumer 处理
- 验证 performance_bisect.py 正确执行

---

## 六、风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 性能噪声导致误报 | Midpoint 算法要求不重叠范围，天然过滤噪声 |
| 样本数不足 | 配置最小样本数要求 (默认 2) |
| 重复任务 | LRU 缓存 + 数据库去重 |
| 配置文件缺失 | 提供默认配置 fallback |

---

## 七、相关文件

| 文件 | 作用 |
|------|------|
| `container/bisect/core/bisect_producer.py` | 生产者实现 |
| `container/bisect/lib/config.py` | 配置项定义 |
| `container/bisect/config/performance_metrics.yaml` | 指标配置 |
| `lkp-tests/programs/bisect-py/performance_bisect.py` | 性能 bisect 执行器 |
| `lkp-tests/programs/bisect-py/bisect_midpoint_step.py` | Midpoint 评估脚本 |
| `kpi-design-reference.md` | KPI 设计参考 (第二阶段) |

---

## 八、评审要点

1. **架构设计是否合理？**
   - 数据流是否清晰
   - 与现有 ErrorBisectProducer 的一致性

2. **Midpoint 算法是否适用？**
   - 不重叠范围检测的有效性
   - 阈值配置的灵活性

3. **配置设计是否满足需求？**
   - 指标配置的完整性
   - 扩展性（第二阶段 KPI）

4. **与 kernel CI 的集成？**
   - baseline/current 识别策略
   - 时间窗口匹配逻辑

---

*文档生成时间: 2025-01-06*
