# Issue: bisect 配置热更新 / 重启边界梳理

## Status: IN PROGRESS

说明：边界梳理与统计已完成，后续待决定哪些配置值得继续改造成热更新。

## 目标

统一识别当前 bisect 服务里哪些配置：

1. 可以运行时直接修改
2. 修改后下一轮自动生效
3. 需要重启进程
4. 在当前部署模型下实际上需要重建容器

这样后续才能决定哪些配置值得改造成热更新。

---

## 一、当前结论

### A. 运行时可直接修改（无需重启）

#### 1. Producer 开关家族

- 代码位置：
  - controller：`container/bisect/app/controllers.py`（`toggle_producer` / `get_producer_status`）
  - gate：`container/bisect/core/task_processor.py`（`get_producer_gate_state` / `bisect_producer`）
- 现状：
  - 通过 `/api/v1/toggle_producer` 可以在运行时切换
  - 支持 1 个全局总开关：`BISECT_PRODUCER_ENABLED`
  - 支持 4 个子 producer 开关：
    - `BISECT_METRICS_PRODUCER_ENABLED`
    - `BISECT_KERNEL_CI_PRODUCER_ENABLED`
    - `BISECT_ERROR_PRODUCER_ENABLED`
    - `PERFORMANCE_PRODUCER_ENABLED`
  - controller 直接修改内存中的 `Config.*`
  - 从全关/全暂停恢复到可运行状态时，必要时还会补起 producer 线程
- 限制：
  - 这是**内存态**修改
  - 容器重启后仍会回到环境变量中的原始值

#### 2. `BISECT_CONSUMER_ENABLED`

- 代码位置：
  - controller：`container/bisect/app/controllers.py`（`toggle_consumer` / `get_consumer_status`）
  - gate：`container/bisect/core/task_processor.py` 中 `_ConsumerWorker.process_cycle` 和 `_ValidatorWorker.process_cycle` 的开头
- 现状：
  - 通过 `/api/v1/toggle_consumer?state=enable|disable` 在运行时切换
  - controller 直接修改内存中的 `Config.BISECT_CONSUMER_ENABLED`
  - `BisectConsumer` 会停止从 `wait` 队列捞新任务
  - `SuccessTaskValidator` 会停止提交新的 verification job，但会继续轮询已提交 job 的结果并做超时回收
  - 两个 worker 都保留常驻线程，不销毁
  - controller 会同时唤醒 consumer / validator 两个 wake event，让状态切换尽快生效
- 语义：
  - 只拦截新的 wait-task 投递和新的 verification 提交，**thread pool 中正在执行的任务不会被取消**（和 producer 关掉不会回收已创建的 wait 任务语义对齐）
  - HeadValidator 不受本开关影响，它有独立的 `BISECT_HEAD_VALIDATOR_ENABLED`
- 限制：
  - 内存态修改，容器重建后会回到环境变量初始值
- 启动默认：
  - `container/bisect/start` 里显式传 `-e BISECT_CONSUMER_ENABLED=true`
  - 同时传 `-e BISECT_CONSUMER_STARTUP_DELAY_SECONDS=300`
  - 这样容器刚起来时仍有 300 秒观察窗口，不会立刻把 wait 队列里的任务拖进 thread pool / repo pool
  - 运维可以在窗口期内手动 `disable_consumer`，延迟结束后仍保持暂停

---

### B. 改文件后下一轮自动生效（无需重启）

#### 1. `container/bisect/config/errid_filters.yaml`

- 读取入口：`container/bisect/lib/errid_intelligence.py:93`
- 生效路径：
  - `ErrorBisectProducer` 每轮都会新建
  - `ErrorBisectProducer.__init__()` 每轮都会重新创建 `ErridIntelligence()`
  - 因此 filter 文件修改后，**下一轮 producer cycle** 就会读到新内容

#### 2. `ci_config.yaml` / `CI_CONFIG_PATH`

- 读取入口：`container/bisect/core/bisect_producer.py:1254`
- 生效路径：
  - `PerformanceBisectProducer` 每轮都会新建
  - `_load_baseline_commits()` 每轮会重新读配置文件
  - 因此基线 tag / matrix 内容修改后，**下一轮 performance producer cycle** 就会生效
- 注意：
  - `CI_CONFIG_PATH` 这个“路径本身”来自环境变量，改路径仍需要重启/重建
  - 这里只是说“文件内容”会热生效

---

### C. 需要重启进程才能生效

#### 1. `container/bisect/lib/config.py` 中的大多数环境变量

- 统计结果：
  - `Config` 里共有 **60 个唯一 env-backed key**
- 原因：
  - `Config` 是类属性，在 import 时读取环境变量
  - Flask API / TaskProcessor / repo manager / validator / producer 都会把这些值缓存到进程内

典型例子：

- producer 调度：
  - `BISECT_PRODUCER_SCHEDULED_ENABLED`
  - `BISECT_PRODUCER_SCHEDULED_TIME`
  - `BISECT_PRODUCER_CYCLE_HOURS`
- 线程和验证：
  - `BISECT_THREADS`
  - `VALIDATION_INTERVAL`
  - `MAX_VERIFYING_TASKS`
  - `VERIFICATION_TIMEOUT_*`
- repo / clone：
  - `BISECT_MAX_CONCURRENT_CLONES`
  - `GIT_CLONE_*`
  - `GIT_PRISTINE_FETCH_INTERVAL`
  - `REPO_POOL_*`
- producer 查询窗口：
  - `BISECT_PRODUCER_QUERY_HOURS`
  - `BISECT_PRODUCER_MAX_QUERY_HOURS`
  - `BISECT_PRODUCER_BATCH_SIZE`
- performance producer：
  - `PERFORMANCE_*`
  - `BASELINE_QUERY_HOURS`
  - `CURRENT_QUERY_HOURS`
- API 查询限制：
  - `DEFAULT_QUERY_LIMIT`
  - `MAX_QUERY_LIMIT`
  - `WAIT_TASK_QUERY_LIMIT`

#### 2. `LOG_LEVEL` / log routing 相关

- 读取入口：`container/bisect/lib/log_config.py:71`
- 原因：
  - logger 初始化时读取环境变量
  - 改动后需要重启对应 Python 进程

#### 3. `WORK_DIR` / `CCI_SRC` / `LKP_SRC` 等路径环境

- 典型入口：
  - `container/bisect/app/__init__.py`
  - `container/bisect/lib/repo_manager.py:40`
  - `container/bisect/core/task_processor.py`
- 原因：
  - 路径被类属性、模块 import 路径、repo manager 初始化过程缓存

---

### D. 在当前部署模型下，实际上需要“重建容器”，不只是重启

即使某些配置理论上只需“重启进程”，但当前部署方式是：

- `container/bisect/start` 通过 `docker run -e ... -v ... -p ...` 创建容器

这意味着：

#### 1. 改 `-e` 传入的环境变量

- 单纯 `docker restart bisect` **不会改变容器环境变量**
- 需要：
  - 修改 `container/bisect/start`
  - 或用新的环境值重新 `docker run`
  - 实际效果上等同于**重建容器**

#### 2. 改 volume / port / supervisord 配置挂载

- `-v ...`
- `-p ...`
- `SUPERVISORD_CONF`

这些也都属于容器创建参数，修改后必须重建容器。

---

## 二、为什么现在会让人误以为“只要 restart 就行”

原因是当前系统同时混着三种配置模型：

1. **运行时内存态开关**
   - 例如 `toggle_producer`
2. **每轮重读文件**
   - 例如 `errid_filters.yaml`
   - 例如 `ci_config.yaml`
3. **启动时快照**
   - 大部分 `Config` 环境变量都属于这一类

如果不明确区分，用户会自然误以为：

- 改环境变量后 `docker restart` 即可

但实际上在 Docker 下：

- 改 env = 通常要**重建容器**

---

## 三、建议的统一化方向

### 方向 1：先统一文档语义（低风险，优先做）

建议把配置分成三类写清楚：

- `runtime mutable`
- `reload on next cycle`
- `requires recreate`

至少在以下文档里统一：

- `container/bisect/README.md`
- `container/bisect/docs/INDEX.md`
- `container/bisect/docs/BISECT_USAGE.md`

---

### 方向 2：把“值得热更新”的配置单独抽出来（中风险）

优先考虑这些高频调参项：

- producer 调度
  - `BISECT_PRODUCER_SCHEDULED_ENABLED`
  - `BISECT_PRODUCER_SCHEDULED_TIME`
  - `BISECT_PRODUCER_CYCLE_HOURS`
- 验证并发 / 超时
  - `MAX_VERIFYING_TASKS`
  - `VERIFICATION_TIMEOUT_*`
- 查询窗口
  - `BISECT_PRODUCER_QUERY_HOURS`
  - `BISECT_PRODUCER_MAX_QUERY_HOURS`

可以考虑：

- 方案 A：独立 YAML + reload endpoint
- 方案 B：数据库配置表 + 周期拉取
- 方案 C：SIGHUP / admin API 触发重新加载

---

### 方向 3：明确哪些配置永远不做热更新（低争议）

建议保持“必须重建容器”的有：

- 路径类
  - `CCI_SRC`
  - `LKP_SRC`
  - `WORK_DIR`
- Docker topology
  - volume mounts
  - exposed ports
- supervisord 进程定义

因为这些本来就和容器拓扑绑定过深。

---

## 四、建议后续动作

### 第一阶段：只补文档

- 写清：
  - 哪些配置改了无需重启
  - 哪些下一轮自动生效
  - 哪些必须重建容器

### 第二阶段：改造成可 reload

优先改这 3 组：

1. producer schedule
2. verification limits/timeouts
3. producer query windows

### 第三阶段：保留容器级 immutable 配置

- Docker env / volume / port
- path 类配置
- supervisord 启动定义

---

## 五、当前统计摘要

- `container/bisect/lib/config.py`：
  - **60 个唯一 env-backed key**
- 当前明确支持运行时切换的配置：
  - **6 个**
    - `BISECT_PRODUCER_ENABLED`
    - `BISECT_METRICS_PRODUCER_ENABLED`
    - `BISECT_KERNEL_CI_PRODUCER_ENABLED`
    - `BISECT_ERROR_PRODUCER_ENABLED`
    - `PERFORMANCE_PRODUCER_ENABLED`
    - `BISECT_CONSUMER_ENABLED`
- 当前明确支持“改文件后下一轮自动生效”的配置文件：
  - **2 个**
    - `errid_filters.yaml`
    - `ci_config.yaml` 内容

---

## 六、结论

当前 bisect 的配置语义并不统一：

- 少量配置可运行时改
- 少量配置下一轮自动生效
- 大多数配置是启动快照
- 在当前 Docker 部署方式下，大多数 env 变更最终都需要**重建容器**

因此这部分确实应该：

1. **先统计**
2. **再分类**
3. **最后选择性做热更新改造**
