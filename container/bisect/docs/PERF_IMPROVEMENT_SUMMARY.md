# Bisect 性能相关改进总结（近期开发）

## （1）算法难点攻克

### 1、难点问题：共享仓库并发一致性与热点竞争

### 2、问题描述
- bisect 执行链路与 commit-time 查询链路都依赖 pristine 仓库，存在跨线程/跨进程并发竞争。
- 同一仓库可能以不同 URL 形式出现（如 `git+https://...` 与 `https://...`），导致锁键不一致，互斥失效。
- 在高并发下会出现 fetch/clone 抖动、提交查询失败、任务尾延迟升高。

### 3、解决方法
- 引入 repo URL 规范化（canonical key），统一锁键与 fetch 节流键。
- 增加跨进程文件锁（`fcntl.flock`），补齐仅线程锁的缺口。
- commit-time service 使用独立 pristine 查询目录，降低与 bisect 主流程资源争用。
- 在 fetch 路径加入 refspec 自愈：自动补齐 `remote.origin.fetch=+refs/*:refs/*`。

---

### 1、难点问题：`verifying` 状态长时间悬挂

### 2、问题描述
- 部分验证子任务已进入终态（如 `abort`、`timeout_boot`），主任务仍停留在 `verifying`。
- 旧逻辑主要依赖大超时窗口回收，导致反馈慢、队列占用高。

### 3、解决方法
- 在批量验证回收逻辑中识别终态失败健康状态：
  - `abort` / `abort_invalid` / `abort_wait` / `abort_provider`
  - `timeout_*`
  - `cancel` / `terminate`
- 命中终态时立即回收（标记 timeout/wait 分支），避免长期卡住。

---

### 1、难点问题：跨仓库误匹配导致错误复用

### 2、问题描述
- 任务聚类与成功缓存若不区分仓库，会出现跨仓库误关联，造成错误复用或错误验证链路。

### 3、解决方法
- 将签名缓存与聚类改为 repo-scoped（按 `(git_url, signature)` 隔离）。

## （2）结果优于 SWO（旧方案）

### 定性改进

- 正确性提升：避免跨仓库错配、减少因仓库状态不一致导致的父提交查询失败。
- 稳定性提升：热点仓库的并发冲突从隐式竞争变为显式互斥控制。
- 时效性提升：`verifying` 终态失败可及时收敛，不再大量等待全局超时窗口。
- 可观测性提升：新增 fetch/锁指标与健康信息，定位性能瓶颈和异常路径更快。

### 量化对比（Producer 管道修复前后，2026-03-16 实测）

| 指标 | 修复前 (3个月停滞) | 修复后 (单轮) | 提升 |
|------|-------------------|-------------|------|
| 查询覆盖 | 1,000 jobs | 15,175 jobs | **15x** |
| 有效处理 | 972 jobs | 12,288 jobs | **12.6x** |
| 去重后候选 | ~300 | 5,969 (318 unique) | **全量覆盖** |
| 任务创建 | 0 (全部 409 阻塞) | 117 首轮 + 持续增长 | **从 0 到可用** |
| Commit 分析 | 仅 linux.commit | linux + makepkg + regex fallback | **完整提取** |
| is_ancestor 延迟 | 逐个串行 HTTP | 服务端 ThreadPool 并行批量 | **N:1 降为 1 次调用** |
| 日志可观测性 | 单文件 bisect_all.log 混合所有组件 | 按组件分目录 + 每阶段结构化报告 | **秒级定位** |

**关键修复项对应提升说明：**

- **查询 15x**：解决 ManticoreSearch `max_matches=1000` 默认截断，改为 keyset pagination 分页查询
- **处理 12.6x**：commit 提取从单字段扩展为多字段 + regex fallback，`no_commit_hash` 从 633 降至 14
- **创建从 0 到可用**：Phase 3b 重置 failed 状态任务 + fallback 改用 replace (upsert) 消除 409 碰撞
- **is_ancestor 批量化**：新增 `POST /api/v1/commit/batch_is_ancestor` 端点，服务端 ThreadPoolExecutor (max_workers=8) 并行执行
- **日志分目录**：consumer/producer/api/commit-service 各自独立目录，TimedRotatingFileHandler 按日轮转

## （3）额外的收益

- 回归测试资产沉淀：覆盖锁、refspec 自愈、终态回收、repo-scope、webhook 通知等关键路径。
- 运维成本下降：开发模式下减少手工清理仓库缓存的频次。
- 系统可扩展性增强：webhook 通知链路已具备基础能力，可对接外部告警平台。
- 文档一致性提升：部署、账号切换、宿主机配置映射路径更清晰，降低交接成本。

## （4）Performance producer 指标交集修复

### 1、问题描述

- `unixbench` 等性能作业可能同时混入新旧两类 metric key：
  - 新格式：`unixbench.RATE.Pipe_Throughput`
  - 旧格式：`unixbench.Pipe_Throughput`
- 旧逻辑按“所有 job 共有的 key 交集”构造 comparison pair。
- 当 baseline 侧混入 legacy job，而 current 侧只有新格式 key 时，合法的 `RATE` 指标会被旧 key 稀释掉，最终漏建任务。

### 2、修复内容

- 在 `container/bisect/core/bisect_producer.py` 新增 `_collect_numeric_suite_metrics()`，先按 job 集合收集“某个 suite 下实际出现过的数值 metric”。
- 在 comparison pair 构建逻辑中，改为分别收集 baseline / current 两侧的数值 metric，再取两侧交集。
- 这样 pair 构建不再依赖“所有 job 都必须同时带同一 key”，而是依赖“两侧都至少出现过有效数值样本”。

### 3、修复效果

- baseline 混入 legacy unixbench job 时，合法的 `unixbench.RATE.Pipe_Throughput` 不再被旧 key 挡掉。
- `unixbench.Pipe_Throughput` 如果只存在于 baseline 侧、current 侧没有，就不会被误认为可比较指标，也不会误建任务。

### 4、回归测试

- `container/bisect/core/tests/test_performance_producer_subtests.py` 增加了专门回归用例：
  - baseline 侧同时混有 `unixbench.RATE.Pipe_Throughput` 和 legacy `unixbench.Pipe_Throughput`
  - current 侧只有 `unixbench.RATE.Pipe_Throughput`
  - 断言最终 comparison pair 保留 `unixbench.RATE.Pipe_Throughput`
  - 断言 legacy `unixbench.Pipe_Throughput` 不进入最终 metrics 集合
