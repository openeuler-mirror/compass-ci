# Bisect 系统测试与使用文档

## 目录

1. [概述](#1-概述)
2. [整体架构与流程](#2-整体架构与流程)
3. [数据流详解](#3-数据流详解)
4. [组件详解](#4-组件详解)
5. [系统指标](#5-系统指标)
6. [API 客户端使用指南](#6-api-客户端使用指南)
7. [案例展示](#7-案例展示)
8. [运维操作](#8-运维操作)
9. [部署指南](#9-部署指南)

---

## 1. 概述

### 1.1 系统目标

Bisect 系统是一个自动化的二分查找系统，用于在代码库中精确定位引入问题的第一个坏提交（First Bad Commit）。系统支持三种类型的问题定位：

- **构建错误（Build）**：编译失败、链接错误、代码警告等
- **功能错误（Functional）**：测试用例失败、运行时错误、启动失败等
- **性能回归（Benchmark）**：性能指标劣化、吞吐量下降、延迟增加等

### 1.2 核心价值

| 价值维度 | 描述 |
|---------|------|
| **自动化** | 全流程自动化，从错误发现到报告生成无需人工干预 |
| **精准定位** | 通过二分查找算法精确定位到引入问题的单个 commit |
| **高效去重** | 智能识别相似错误，避免重复执行 bisect 操作 |
| **结果验证** | 多层验证机制确保定位结果的准确性 |
| **可追溯** | 完整的任务生命周期记录和报告输出 |

### 1.3 适用场景

- Linux 内核日常构建测试的错误定位
- 功能测试套件（LTP、xfstests、kernel-selftests 等）失败分析
- 性能回归问题的根因定位
- 大规模持续集成环境下的自动化问题追踪

---

## 2. 整体架构与流程

### 2.1 系统流程图

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Bisect 系统整体流程                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐    ┌─────────────┐
│   Kernel CI  │───▶│  Bisect Producer │───▶│  Bisect Consumer │───▶│  Validators │
│  (生产任务)   │    │  (筛选与识别)     │    │   (执行 Bisect)   │    │  (结果验证)  │
└──────────────┘    └──────────────────┘    └──────────────────┘    └──────┬──────┘
       │                    │                       │                      │
       ▼                    ▼                       ▼                      ▼
  ┌─────────┐         ┌─────────┐            ┌───────────┐          ┌───────────┐
  │  Jobs   │         │ Bisect  │            │ Regression│          │  Report   │
  │  Table  │         │  Table  │            │   Table   │          │  Output   │
  └─────────┘         └─────────┘            └───────────┘          └───────────┘
```

### 2.2 详细流程说明

```
                                    ┌─────────────────┐
                                    │    Kernel CI    │
                                    │   日常测试任务   │
                                    └────────┬────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │   Jobs Table    │
                                    │  (失败任务记录)  │
                                    └────────┬────────┘
                                             │
                          ┌──────────────────┼──────────────────┐
                          │                  │                  │
                          ▼                  ▼                  ▼
                   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
                   │ Build Error │   │ Boot Error  │   │ Test Error  │
                   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
                          │                  │                  │
                          └──────────────────┼──────────────────┘
                                             │
                                    ┌────────┴────────┐
                                    │                 │
                                    ▼                 ▼
                          ┌─────────────────┐ ┌─────────────────┐
                          │   Error Type    │ │ Performance Type│
                          │   (error_id)    │ │ (bisect_metric) │
                          └────────┬────────┘ └────────┬────────┘
                                   │                   │
                                   └─────────┬─────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │ Bisect Producer │
                                    │  ┌───────────┐  │
                                    │  │ 智能筛选  │  │
                                    │  │ 优先级≥35 │  │
                                    │  │ 批量去重  │  │
                                    │  └───────────┘  │
                                    └────────┬────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │  Bisect Table   │
                                    │  status: wait   │
                                    └────────┬────────┘
                                             │
                          ┌──────────────────┴──────────────────┐
                          │                                     │
                          ▼                                     ▼
                 ┌─────────────────┐                   ┌─────────────────┐
                 │ Bisect Consumer │                   │    相似任务      │
                 │ status:processing│                  │ status:verifying │
                 │  ┌───────────┐  │                   └────────┬────────┘
                 │  │ 任务聚类  │  │                            │
                 │  │ 执行bisect│  │                            │
                 │  │ 边界验证  │  │                            │
                 │  └───────────┘  │                            │
                 └────────┬────────┘                            │
                          │                                     │
                          ▼                                     │
                 ┌─────────────────┐                            │
                 │ first_bad_commit│◀───────────────────────────┘
                 │ status: success │      (复用验证结果)
                 └────────┬────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │   Success Validator   │
              │  ┌─────────────────┐  │
              │  │ 边界测试验证    │  │
              │  │ parent=good     │  │
              │  │ candidate=bad   │  │
              │  └─────────────────┘  │
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │    Regression Table   │
              │   + Report Generation │
              └───────────────────────┘
```

### 2.3 状态流转

```
┌──────────────────────────────────────────────────────────────────┐
│                        任务状态流转图                             │
└──────────────────────────────────────────────────────────────────┘

                              ┌─────────┐
                              │  wait   │ ◀─────────────────────┐
                              └────┬────┘                       │
                                   │                            │
                    ┌──────────────┴──────────────┐             │
                    │                             │             │
                    ▼                             ▼             │
             ┌────────────┐               ┌────────────┐        │
             │ processing │               │ verifying  │        │
             └─────┬──────┘               └─────┬──────┘        │
                   │                            │               │
         ┌─────────┴─────────┐        ┌─────────┴─────────┐     │
         │                   │        │                   │     │
         ▼                   ▼        ▼                   │     │
   ┌──────────┐       ┌──────────┐  验证成功              │     │
   │ success  │       │  failed  │    │                   │     │
   └──────────┘       └──────────┘    ▼                   │     │
                                ┌──────────┐              │     │
                                │ success  │         验证失败    │
                                │(复用结果) │              │     │
                                └──────────┘              └─────┘
```

---

## 3. 数据流详解

本章节详细描述 Bisect 系统中各组件之间的数据流转，包括每个组件的输入、输出和数据格式。

### 3.1 整体数据流图

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    Bisect 系统数据流                                          │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────┐          ┌─────────────┐          ┌─────────────┐          ┌─────────────┐
│  Kernel CI  │          │   Producer  │          │   Consumer  │          │  Validators │
│             │          │             │          │             │          │             │
│ ┌─────────┐ │          │ ┌─────────┐ │          │ ┌─────────┐ │          │ ┌─────────┐ │
│ │ 测试执行 │ │          │ │ 任务筛选 │ │          │ │ Bisect  │ │          │ │ 结果验证 │ │
│ └────┬────┘ │          │ └────┬────┘ │          │ └────┬────┘ │          │ └────┬────┘ │
└──────┼──────┘          └──────┼──────┘          └──────┼──────┘          └──────┼──────┘
       │                        │                        │                        │
       ▼                        ▼                        ▼                        ▼
┌─────────────┐          ┌─────────────┐          ┌─────────────┐          ┌─────────────┐
│  Jobs Table │─────────▶│Bisect Table │─────────▶│Bisect Table │─────────▶│ Regression  │
│  (失败记录)  │          │ (wait任务)  │          │ (success)   │          │   Table     │
└─────────────┘          └─────────────┘          └─────────────┘          └─────────────┘
       │                        │                        │                        │
       │                        │                        │                        │
       ▼                        ▼                        ▼                        ▼
┌─────────────┐          ┌─────────────┐          ┌─────────────┐          ┌─────────────┐
│ error_ids   │          │ bisect_task │          │first_bad_   │          │ bisect_     │
│ job_state   │          │ status:wait │          │  commit     │          │  report     │
│ result_root │          │ priority    │          │ introduced_ │          │ regression_ │
│ stats       │          │ error_id    │          │   errids    │          │   record    │
└─────────────┘          └─────────────┘          └─────────────┘          └─────────────┘
```

### 3.2 数据流转详细说明

#### 阶段 1：测试执行与失败记录

```
                    ┌─────────────────────┐
                    │      Kernel CI      │
                    │    (测试执行引擎)    │
                    └──────────┬──────────┘
                               │
            ┌──────────────────┼──────────────────┐
            │                  │                  │
            ▼                  ▼                  ▼
     ┌────────────┐     ┌────────────┐     ┌────────────┐
     │ 构建测试    │     │ 功能测试    │     │ 性能测试    │
     │ Build      │     │ Functional │     │ Benchmark  │
     └─────┬──────┘     └─────┬──────┘     └─────┬──────┘
           │                  │                  │
           │ error_ids        │ error_ids        │ stats
           │ build_state      │ job_state        │ compare_result
           │                  │                  │
           └──────────────────┼──────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │     Jobs Table      │
                    │   (ES/数据库存储)    │
                    └─────────────────────┘
```

**输出数据格式 (Jobs Table)**：

```json
{
  "job_id": "25121622004840300",
  "suite": "ltp",
  "job_state": "failed",
  "error_ids": [
    "ltp.eid.syscalls.recvmsg01:fail",
    "ltp.eid.syscalls.sendmsg03:fail"
  ],
  "stats": {
    "ltp.syscalls.recvmsg01.fail": 1,
    "ltp.syscalls.sendmsg03.fail": 1
  },
  "upstream_commit": "abc123def456",
  "result_root": "/result/ltp/2025-12-16/...",
  "submit_time": 1765788000,
  "testbox": "vm-2p8g",
  "os": "openeuler-24.03",
  "os_arch": "aarch64"
}
```

#### 阶段 2：任务识别与创建

```
┌─────────────────────┐                    ┌─────────────────────┐
│     Jobs Table      │                    │    Bisect Table     │
│                     │                    │                     │
│  job_state=failed   │═══════════════════▶│   status=wait       │
│  error_ids          │    Producer        │   error_id          │
│  upstream_commit    │    (筛选与创建)     │   bad_job_id        │
│  result_root        │                    │   priority_level    │
└─────────────────────┘                    └─────────────────────┘
         │                                          │
         │ 输入                                      │ 输出
         ▼                                          ▼
┌─────────────────────┐                    ┌─────────────────────┐
│ • failed jobs       │                    │ • bisect_task       │
│ • error_ids 列表     │                    │ • status: wait      │
│ • commit 信息        │                    │ • priority_level    │
│ • stats 数据         │                    │ • category          │
└─────────────────────┘                    └─────────────────────┘
```

**Producer 筛选流程**：

```
输入: Jobs Table (failed jobs, 最近24小时)
  │
  ├──▶ 优先级过滤 (priority ≥ 35)
  │     │
  │     └──▶ 优先级计算规则：
  │           • has_file_path: +30 分（包含源文件路径如 xxx.c:123:45）
  │           • critical_level: +40 分（包含 error, fatal, panic）
  │           • high_level: +25 分（包含 warning, fail）
  │           • medium_level: +15 分（包含 warn, deprecated）
  │           • code_related: +20 分（编译/链接相关错误）
  │           • appropriate_length: +10 分（错误信息长度 80-300）
  │           • whitelist_match: +20 分（匹配高价值错误白名单）
  │           • 环境错误黑名单: 直接过滤（网络、权限、安装错误等）
  │
  ├──▶ 批量去重检查 (数据库已存在?)
  │
  ├──▶ Commit 年龄过滤 (< 365天)
  │
  └──▶ 输出: Bisect Table (wait 任务)
```

**优先级计算示例**：

| error_id 示例 | 计算过程 | 最终优先级 |
|--------------|---------|-----------|
| `stderr.eid.kernel/sched/fair.c:#:#:error:xxx` | file_path(30) + critical(40) + code(20) = 90 | 90 |
| `makepkg.eid.xxx.c:warning:implicit-declaration` | file_path(30) + high(25) + warning_boost(10) = 65 | 65 |
| `stderr.eid.curl:(#)The_requested_URL_returned_error` | 环境黑名单匹配 | 0 (过滤) |

**输出数据格式 (Bisect Task)**：

```json
{
  "bad_job_id": "25121622004840300",
  "error_id": "ltp.eid.syscalls.recvmsg01:fail",
  "bisect_status": "wait",
  "category": "function",
  "git_url": "git://xxx/linux.git",
  "upstream_commit": "abc123def456",
  "submit_time": 1765788194,
  "priority_level": 45,
  "work_dir": null,
  "first_bad_commit": null
}
```

#### 阶段 3：Bisect 执行

```
┌─────────────────────┐                    ┌─────────────────────┐
│    Bisect Table     │                    │    Bisect Table     │
│                     │                    │                     │
│   status=wait       │═══════════════════▶│   status=success    │
│   error_id          │    Consumer        │   first_bad_commit  │
│   bad_job_id        │   (执行 bisect)    │   first_bad_id      │
│   upstream_commit   │                    │   first_result_root │
└─────────────────────┘                    └─────────────────────┘
         │                                          │
         │ 输入                                      │ 输出
         ▼                                          ▼
┌─────────────────────┐                    ┌─────────────────────┐
│ • wait 任务          │                    │ • first_bad_commit  │
│ • git_url           │                    │ • first_bad_id      │
│ • upstream_commit   │                    │ • first_result_root │
│ • error_id          │                    │ • status: success/  │
│ • category          │                    │          failed     │
└─────────────────────┘                    └─────────────────────┘
```

**Consumer 执行流程**：

```
输入: Bisect Table (status=wait)
  │
  ├──▶ 任务聚类 (相似错误分组)
  │      │
  │      ├──▶ 代表任务 → status: processing → 执行完整 bisect
  │      │
  │      └──▶ 相似任务 → status: verifying → 等待复用结果
  │
  ├──▶ Git 仓库操作
  │      │
  │      ├──▶ 获取仓库实例 (RepoPool)
  │      │
  │      └──▶ 执行 git bisect run
  │
  ├──▶ 边界验证
  │      │
  │      ├──▶ parent_commit → 提交测试任务 → 期望: good
  │      │
  │      └──▶ first_bad_commit → 提交测试任务 → 期望: bad
  │
  └──▶ 输出: Bisect Table (status=success/failed)
```

**执行结果数据格式**：

```json
{
  "bisect_status": "success",
  "first_bad_commit": "433c0b72564239cf3086f563d5ca32a10e4ffd3f",
  "first_bad_id": "25121112063620900",
  "first_result_root": "/result/makepkg/2025-12-11/...",
  "updated_at": 1765789281,
  "bisect_steps": 8,
  "work_dir": "/bisect_repos/linux/instance_1"
}
```

#### 阶段 4：结果验证与报告

```
┌─────────────────────┐                    ┌─────────────────────┐
│    Bisect Table     │                    │  Regression Table   │
│                     │                    │                     │
│   status=success    │═══════════════════▶│   regression_id     │
│   first_bad_commit  │    Validators      │   first_bad_commit  │
│   first_bad_id      │   (结果验证)        │   introduced_errids │
│                     │                    │   report            │
└─────────────────────┘                    └─────────────────────┘
         │                                          │
         │ 输入                                      │ 输出
         ▼                                          ▼
┌─────────────────────┐                    ┌─────────────────────┐
│ • success 任务       │                    │ • verified 状态     │
│ • first_bad_commit  │                    │ • introduced_errids │
│ • first_bad_id      │                    │ • regression 记录   │
│ • category          │                    │ • bisect 报告       │
└─────────────────────┘                    └─────────────────────┘
```

**Validators 验证流程**：

```
输入: Bisect Table (status=success, pending_verification)
  │
  ├──▶ 批量提交验证作业
  │      │
  │      ├──▶ parent_commit job → 期望: good (无错误)
  │      │
  │      └──▶ candidate_commit job → 期望: bad (有错误)
  │
  ├──▶ 验证结果判定
  │      │
  │      ├──▶ 验证通过 → verification_status: verified
  │      │
  │      └──▶ 验证失败 → 回退到 wait 重新执行
  │
  ├──▶ 计算 introduced_errids (该 commit 引入的所有错误)
  │
  └──▶ 输出: Regression Table + Bisect Report
```

**验证结果数据格式**：

```json
{
  "j": {
    "verification_status": "verified",
    "verified_at": 1765789281,
    "introduced_errids": [
      "makepkg.eid.kernel/sched/fair.c:error:xxx",
      "stderr.eid.kernel/sched/fair.c:error:xxx"
    ],
    "parent_job_id": "25121112063150400",
    "candidate_job_id": "25121112063620900",
    "verification_method": "batch_async_validation",
    "job_request_count": 2,
    "is_result_reused": false,
    "job_reused_rate": 0
  }
}
```

### 3.3 组件间数据接口汇总

| 源组件 | 目标组件 | 数据载体 | 关键字段 |
|-------|---------|---------|---------|
| Kernel CI | Jobs Table | ES 文档 | job_id, error_ids, job_state, stats |
| Jobs Table | Producer | ES 查询 | job_state=failed, error_ids, upstream_commit |
| Producer | Bisect Table | 数据库写入 | bad_job_id, error_id, status=wait, priority |
| Bisect Table | Consumer | 数据库查询 | status=wait, git_url, upstream_commit |
| Consumer | Bisect Table | 数据库更新 | first_bad_commit, status=success/failed |
| Consumer | Kernel CI | 验证作业 | commit, test_suite, expected_result |
| Bisect Table | Validators | 数据库查询 | status=success, pending_verification |
| Validators | Regression Table | 数据库写入 | regression_id, introduced_errids |
| Validators | 报告系统 | 文件输出 | bisect_report.txt |

### 3.4 数据状态流转图

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│                              数据状态完整流转                                        │
└────────────────────────────────────────────────────────────────────────────────────┘

Jobs Table                  Bisect Table                         Output
──────────────────────────────────────────────────────────────────────────────────────

job_state: failed    ──▶    status: wait         ──┬──▶    status: processing
                                                   │              │
                                                   │         ┌────┴────┐
                                                   │         ▼         ▼
                                                   │    status:    status:
                                                   │    success    failed
                                                   │         │         │
                                                   │         ▼         │
                                                   │    verification   │
                                                   │    _status:       │
                                                   │    pending        │
                                                   │         │         │
                                                   │         ▼         │
                                                   │    verification   │
                                                   │    _status:       │
                                                   │    verified       │
                                                   │         │         │
                                                   │         ▼         ▼
                                                   │    ┌─────────────────┐
                            status: verifying  ────┘    │ Regression Table│
                                   │                    │ + Bisect Report │
                                   │                    └─────────────────┘
                                   │
                        ┌──────────┴──────────┐
                        ▼                     ▼
                   验证成功                验证失败
                   复用 first_bad_commit   回退到 wait
                        │
                        ▼
                   status: success
                   (is_result_reused: true)
```

---

## 4. 组件详解

### 4.1 Kernel CI（任务来源）

Kernel CI 是 Bisect 系统的上游数据源，负责执行各类内核测试并记录结果。

#### 输入/输出

| 类型 | 描述 | 数据格式 |
|-----|------|---------|
| **输入** | 测试配置 (YAML) | job.yaml 文件 |
| **输入** | 内核源码 | Git 仓库 URL + commit |
| **输出** | 测试结果 | Jobs Table 记录 |
| **输出** | 错误标识 | error_ids 列表 |
| **输出** | 性能数据 | stats 字典 |

**测试类型**：

| 类型 | 说明 | 示例测试套件 |
|-----|------|-------------|
| **构建测试** | 内核编译验证 | allmodconfig, allyesconfig, randconfig |
| **功能测试** | 运行时功能验证 | LTP, xfstests, kernel-selftests, trinity |
| **性能测试** | 性能基准对比 | unixbench, lmbench, iozone, fio |

**数据流向**：
- 测试完成后，结果写入 `jobs` 表
- 失败任务的 `error_ids` 字段记录所有检测到的错误

### 4.2 Bisect Producer（任务筛选与识别）

Producer 负责从失败任务中识别和创建有价值的 bisect 任务。

#### 代码位置

| 文件 | 说明 |
|-----|------|
| `container/bisect/core/bisect_producer.py` | Producer 核心实现 |
| `container/bisect/lib/errid_intelligence.py` | error_id 优先级评分 |
| `container/bisect/lib/producer_reporter.py` | 统计报告生成 |
| `container/bisect/lib/batch_inserter.py` | 批量任务插入 |

#### 输入/输出

| 类型 | 描述 | 数据格式 | 来源/目标 |
|-----|------|---------|----------|
| **输入** | 失败的 jobs 列表 | ES 查询结果 | Jobs Table (job_state=failed) |
| **输入** | error_ids 列表 | 字符串数组 | job.error_ids 字段 |
| **输入** | 性能比较结果 | stats 字典 | job.stats 字段 |
| **输出** | bisect 任务 | 数据库记录 | Bisect Table (status=wait) |
| **输出** | 统计报告 | 文本文件 | /srv/result/bisect/producer_stats/ |

**核心功能**：

1. **查询失败任务**：扫描最近 24 小时内的失败 jobs
2. **智能筛选 error_ids**：
   - 优先级评分机制（优先级 ≥ 35）
   - 每个 job 最多处理 150 个 error_id
3. **批量去重**：检查数据库中是否已存在相同任务
4. **Commit 年龄过滤**：跳过超过 365 天的旧 commit
5. **批量创建任务**：写入 `bisect` 表，状态为 `wait`

**执行周期**：每 24 小时运行一次

**关键配置**：

```bash
# 环境变量
BISECT_PRODUCER_ENABLED=true      # 启用/禁用 Producer
BISECT_PRODUCER_INTERVAL=86400    # 运行间隔（秒）
```

### 4.3 Bisect Consumer（任务执行）

Consumer 是系统的核心执行引擎，负责执行实际的 git bisect 操作。

#### 代码位置

| 文件 | 说明 |
|-----|------|
| `container/bisect/core/bisect_consumer.py` | Consumer 核心实现 |
| `container/bisect/core/task_processor.py` | 任务处理逻辑 |
| `container/bisect/lib/repo_manager.py` | Git 仓库管理 |
| `container/bisect/lib/bisect_utils.py` | bisect 工具函数 |
| `container/bisect/app/submit_tasks_api.py` | 测试任务提交 |

#### 输入/输出

| 类型 | 描述 | 数据格式 | 来源/目标 |
|-----|------|---------|----------|
| **输入** | 待处理任务 | 数据库记录 | Bisect Table (status=wait) |
| **输入** | Git 仓库 | 本地仓库克隆 | RepoPool 管理 |
| **输入** | 测试任务结果 | job 状态 | Kernel CI 返回 |
| **输出** | first_bad_commit | commit hash | Bisect Table 更新 |
| **输出** | 任务状态 | success/failed | Bisect Table 更新 |
| **输出** | 验证任务 | job 请求 | Kernel CI 提交 |

**核心功能**：

1. **任务获取**：查询 `status=wait` 的任务
2. **任务聚类**：
   - 基于错误签名（`file_path::error_type`）分组
   - 每组选择一个代表任务执行完整 bisect
   - 其他相似任务标记为 `verifying`
3. **执行 bisect**：
   - 克隆仓库（使用 `--reference` 优化）
   - 二分查找定位 first_bad_commit
4. **边界验证**：
   - 验证 parent_commit 为 good
   - 验证 first_bad_commit 为 bad

**执行周期**：持续运行，指数退避（30s → 60s → 120s → 240s → 300s）

**关键配置**：

```bash
# 环境变量
BISECT_THREADS=32                        # 并发线程数
BISECT_MAX_CONCURRENT_CLONES=4           # 最大并发克隆数
GIT_CLONE_PRISTINE_TIMEOUT=7200          # 克隆超时（秒）
```

### 4.4 Validators（结果验证）

#### 代码位置

| 文件 | 说明 |
|-----|------|
| `container/bisect/core/verification_consumer.py` | Verification Consumer 实现 |
| `container/bisect/validators/success_task_validator.py` | Success Task Validator 实现 |
| `container/bisect/validators/head_validator.py` | HEAD 验证器 |
| `container/bisect/validators/task_optimizer.py` | 任务优化器 |

#### 输入/输出

| 类型 | 描述 | 数据格式 | 来源/目标 |
|-----|------|---------|----------|
| **输入** | verifying 任务 | 数据库记录 | Bisect Table (status=verifying) |
| **输入** | success 任务 | 数据库记录 | Bisect Table (status=success) |
| **输入** | 验证作业结果 | job 状态 | Kernel CI 返回 |
| **输出** | 验证状态 | verified/pending | j.verification_status 字段 |
| **输出** | introduced_errids | 字符串数组 | j.introduced_errids 字段 |
| **输出** | Regression 记录 | 数据库记录 | Regression Table |
| **输出** | Bisect 报告 | 文本文件 | /srv/result/bisect/reports/ |

#### 4.4.1 Verification Consumer

处理 `verifying` 状态的任务，验证是否可以复用已有的 first_bad_commit。

**验证逻辑**：
1. 获取关联任务的 `first_bad_commit`
2. 提交两个验证作业：
   - `parent_commit`：期望结果为 good
   - `candidate_commit`：期望结果为 bad
3. 验证成功 → 复用结果，标记为 `success`
4. 验证失败 → 回退到 `wait`，执行完整 bisect

#### 4.4.2 Success Task Validator

对成功完成的任务进行最终验证和结果分析。

**核心功能**：
1. 批量提交验证作业
2. 计算 `introduced_errids`（该 commit 引入的所有错误）
3. 更新验证状态和结果

**关键配置**：

```bash
# 环境变量
PARALLEL_VERIFICATION_JOBS=200    # 并行验证作业数
VERIFICATION_BATCH_SIZE=200       # 验证批量大小
```

---

## 5. 系统指标

### 5.1 指标定义

| 指标名称 | 定义 | 计算方式 |
|---------|------|---------|
| **Success Rate** | 成功率 | 成功任务数 / 总任务数 × 100% |
| **Miss Rate** | 漏检率 | 未能定位的任务数 / 总任务数 × 100% |
| **Duplicate Rate** | 重复率 | 重复任务数 / 独立问题数 × 100% |
| **Timeliness (90%)** | 时效性 | 90% 任务从创建到完成的时间 |

### 5.2 Build Bisect 指标

构建错误的 bisect 任务指标要求：

| 指标 | 目标值 | 说明 |
|-----|-------|------|
| Success Rate | ≥ 95% | 构建错误通常具有确定性，成功率应较高 |
| Miss Rate | ≤ 10% | 允许少量无法定位的边缘情况 |
| Duplicate Rate | ≤ 2 | 同一问题最多允许 2 个重复任务 |
| Timeliness (90%) | ≤ 1 day | 90% 的任务应在 1 天内完成 |

**典型指标报告**：

```
--- Build Bisect Metrics ---
Total Tasks: 168

Target Requirements:
  - Success Rate: ≥95%
  - Miss Rate: ≤10%
  - Duplicate Rate: ≤2
  - Timeliness (90%): ≤1 day(s)

Actual Metrics:
  - Success Rate: 100.00% (target: ≥95%) ✓ PASS
  - Miss Rate: 0.00% (target: ≤10%) ✓ PASS
  - Timeliness (90%): 0.19 days (target: ≤1 day(s)) ✓ PASS
  - Duplicate Rate: 1.5 (target: ≤2) ✓ PASS

Overall Assessment: ✓ ALL TARGETS MET
```

### 5.3 Functional Bisect 指标

功能测试错误的 bisect 任务指标要求：

| 指标 | 目标值 | 说明 |
|-----|-------|------|
| Success Rate | ≥ 80% | 功能测试可能存在偶发性，成功率略低 |
| Miss Rate | ≤ 20% | 允许更多的不确定性 |
| Duplicate Rate | ≤ 3 | 同一问题最多允许 3 个重复任务 |
| Timeliness (90%) | ≤ 5 days | 功能测试执行时间较长 |

**典型指标报告**：

```
--- Functional Bisect Metrics ---
Total Tasks: 42

Target Requirements:
  - Success Rate: ≥80%
  - Miss Rate: ≤20%
  - Duplicate Rate: ≤3
  - Timeliness (90%): ≤5 day(s)

Actual Metrics:
  - Success Rate: 100.00% (target: ≥80%) ✓ PASS
  - Miss Rate: 0.00% (target: ≤20%) ✓ PASS
  - Timeliness (90%): 0.07 days (target: ≤5 day(s)) ✓ PASS
  - Duplicate Rate: 1.2 (target: ≤3) ✓ PASS

Overall Assessment: ✓ ALL TARGETS MET
```

### 5.4 Performance Bisect 指标

性能回归的 bisect 任务指标要求：

| 指标 | 目标值 | 说明 |
|-----|-------|------|
| Success Rate | ≥ 20% | 性能测试存在较大波动性，成功率要求较低 |
| Miss Rate | ≤ 30% | 允许较大的不确定性 |
| Duplicate Rate | ≤ 9 | 同一问题最多允许 9 个重复任务 |
| Timeliness (90%) | ≤ 20 days | 性能测试需要多次运行取均值，周期较长 |

**性能 Bisect 特殊说明**：

- 性能回归使用 `bisect_metric` 字段标识具体的性能指标
- `direction` 字段标识性能变化方向：
  - `worse`：性能变差（如延迟增加、吞吐量下降）
  - `better`：性能变好（用于定位性能提升的 commit）
- 性能测试需要多次运行以减少波动影响
- 由于性能测试的不确定性较高，指标要求相对宽松

### 5.5 Producer 统计指标

| 指标 | 说明 | 正常范围 |
|------|------|----------|
| jobs_processed | 处理的失败 jobs 数量 | 取决于系统规模 |
| tasks_created_success | 成功创建的 bisect 任务 | - |
| 转化率 | 创建任务 / 处理 jobs | 成熟系统: 0.5-5%，新系统: >5% |
| 筛选效率 | 过滤噪音比例 | 优秀: >90%，良好: 80-90% |
| 去重率 | 数据库已存在的比例 | 成熟系统: >80%，新系统: <80% |

---

## 6. API 客户端使用指南

### 6.1 环境配置

```bash
# 设置 API 服务器地址（默认: localhost:9999）
export BISECT_API_HOST="your-server:9999"

# 确保已安装 requests 库
pip3 install requests
```

### 6.2 任务管理命令

#### 创建新任务

```bash
# 创建错误类型任务（使用 error_id）
python3 sbin/bisect_api.py new_task --bad_job_id 123456 --error_id "compile_error"

# 创建性能类型任务（使用 metric）
python3 sbin/bisect_api.py new_task --bad_job_id 123456 --metric "hackbench.throughput"
python3 sbin/bisect_api.py new_task --bad_job_id 123456 --metric "unixbench.score"
python3 sbin/bisect_api.py new_task --bad_job_id 123456 --metric "fio.read_bw"

# 从 JSON 文件读取
python3 sbin/bisect_api.py new_task -f task.json

# 直接传入 JSON 字符串（错误类型）
python3 sbin/bisect_api.py new_task -j '{"bad_job_id":"123456","error_id":"test.error"}'

# 直接传入 JSON 字符串（性能类型）
python3 sbin/bisect_api.py new_task -j '{"bad_job_id":"123456","bisect_metric":"hackbench.throughput"}'
```

**注意**：`error_id` 和 `bisect_metric` 参数互斥，只能指定其中一个。

#### 查询任务列表

```bash
# 查询所有任务
python3 sbin/bisect_api.py list_tasks

# 按状态筛选
python3 sbin/bisect_api.py list_tasks --status success
python3 sbin/bisect_api.py list_tasks --status failed
python3 sbin/bisect_api.py list_tasks --status wait

# 按类型筛选
python3 sbin/bisect_api.py list_tasks --category build
python3 sbin/bisect_api.py list_tasks --category function

# 按时间筛选
python3 sbin/bisect_api.py list_tasks --hours 24

# 按完整 error_id 精确筛选（支持特殊字符）
python3 sbin/bisect_api.py list_tasks --error_id "stderr.eid.fs/#p/vfs_file.c:warning"

# 按 commit 筛选
python3 sbin/bisect_api.py list_tasks --commit bbaaa756ad25

# 组合筛选
python3 sbin/bisect_api.py list_tasks --status failed --category build --hours 48
python3 sbin/bisect_api.py list_tasks --git_url "https://github.com/torvalds/linux.git" --status success
```

说明：
- `--error_id` 为精确匹配，应传入完整 `error_id`
- 特殊字符会由客户端自动完成 URL 编码

#### 删除任务

```bash
# 按 ID 删除
python3 sbin/bisect_api.py delete_tasks --id 1001

# 按完整 error_id 删除
python3 sbin/bisect_api.py delete_tasks --error_id "test.error"

# 按 commit 删除
python3 sbin/bisect_api.py delete_tasks --commit bbaaa756ad25

# 组合条件删除
python3 sbin/bisect_api.py delete_tasks --status failed --category build

# 非交互环境跳过确认
python3 sbin/bisect_api.py delete_tasks --id 1001 --yes
```

### 6.3 状态重置命令

```bash
# 重置所有失败任务
python3 sbin/bisect_api.py reset_failed

# 非交互环境跳过确认
python3 sbin/bisect_api.py reset_failed --yes

# 重置 processing 状态任务
python3 sbin/bisect_api.py reset_processing

# 重置 verifying 状态任务
python3 sbin/bisect_api.py reset_verifying

# 重置 pending_verification 状态任务
python3 sbin/bisect_api.py reset_pending_verification

# 清理孤立的 verifying 任务
python3 sbin/bisect_api.py cleanup_orphaned_verifying

# 按条件重置任务
python3 sbin/bisect_api.py reset_tasks --id 12345
python3 sbin/bisect_api.py reset_tasks --commit bbaaa756ad25
python3 sbin/bisect_api.py reset_tasks --status failed --category build

# 手动设置任务为 verifying 状态
python3 sbin/bisect_api.py set_verifying --ids 12345 67890
```

### 6.4 系统控制命令

```bash
# 查看线程池状态
python3 sbin/bisect_api.py thread_status

# 生产者控制
python3 sbin/bisect_api.py enable_producer
python3 sbin/bisect_api.py disable_producer
python3 sbin/bisect_api.py producer_status
python3 sbin/bisect_api.py trigger_producer          # 手动触发
python3 sbin/bisect_api.py trigger_producer --force  # 强制触发

# 仓库池管理
python3 sbin/bisect_api.py pool_status
python3 sbin/bisect_api.py pool_stats
python3 sbin/bisect_api.py pool_verify
python3 sbin/bisect_api.py pool_cleanup --dry-run
python3 sbin/bisect_api.py pool_cleanup --execute --max-age-days 0.5

# 池监控控制
python3 sbin/bisect_api.py pool_monitor_start
python3 sbin/bisect_api.py pool_monitor_stop
```

---

## 7. 案例展示

### 7.1 Kernel CI 产物案例

以下是典型的 Linux 内核日常测试摘要：

```
======================================
Linux 内核日常测试摘要 - 20251216
开始时间: 2025-12-16 22:00:22
======================================
[22:00:48] 功能测试: openeuler-kernel/OLK-5.10/ltp (tag: 5.10.0-295.0.0, job_id: 25121622004840300)
[22:01:18] 功能测试: openeuler-kernel/OLK-5.10/trinity (tag: 5.10.0-295.0.0, job_id: 25121622011820500)
[22:01:33] 功能测试: openeuler-kernel/OLK-5.10/xfstests (tag: 5.10.0-295.0.0, job_id: 25121622013357800)
[22:01:38] 功能测试: openeuler-kernel/OLK-5.10/cpu-hotplug (tag: 5.10.0-295.0.0, job_id: 25121622013850200)
[22:01:46] 功能测试: openeuler-kernel/OLK-5.10/kernel-selftests (tag: 5.10.0-295.0.0, job_id: 25121622014613300)
[22:01:55] 性能测试: openeuler-kernel/OLK-5.10/unixbench (baseline: 5.10.0-216.0.0, current: 5.10.0-295.0.0)
[22:02:10] 性能测试: openeuler-kernel/OLK-5.10/lmbench (baseline: 5.10.0-216.0.0, current: 5.10.0-295.0.0)
[22:02:19] 性能测试: openeuler-kernel/OLK-5.10/iozone (baseline: 5.10.0-216.0.0, current: 5.10.0-295.0.0)
[22:05:56] 性能测试: openeuler-kernel/OLK-5.10/fio (baseline: 5.10.0-216.0.0, current: 5.10.0-295.0.0)
[22:06:01] 构建测试: openeuler-kernel/OLK-5.10/allmodconfig (tag: 5.10.0-295.0.0, job_id: 25121622060111500)
[22:06:05] 构建测试: openeuler-kernel/OLK-5.10/allyesconfig (tag: 5.10.0-295.0.0, job_id: 25121622060561800)
[22:06:10] 构建测试: openeuler-kernel/OLK-5.10/allnoconfig (tag: 5.10.0-295.0.0, job_id: 25121622061023700)
[22:06:14] 构建测试: openeuler-kernel/OLK-5.10/randconfig-20251216-1 (tag: 5.10.0-295.0.0, job_id: 25121622061468600)
[22:06:19] 构建测试: openeuler-kernel/OLK-5.10/randconfig-20251216-2 (tag: 5.10.0-295.0.0, job_id: 25121622061914700)
[22:06:23] 构建测试: openeuler-kernel/OLK-5.10/randconfig-20251216-3 (tag: 5.10.0-295.0.0, job_id: 25121622062364400)
```

**测试类型说明**：

| 类型 | 用途 | 典型测试套件 |
|-----|------|-------------|
| 功能测试 | 验证内核功能正确性 | ltp, xfstests, kernel-selftests, trinity, cpu-hotplug |
| 性能测试 | 性能基准对比 | unixbench, lmbench, iozone, fio |
| 构建测试 | 编译验证 | allmodconfig, allyesconfig, allnoconfig, randconfig |

### 7.2 Bisect 任务生命周期案例

#### 阶段 1：任务创建（wait）

任务由 Producer 从失败的 job 中识别并创建：

```json
{
  "bad_job_id": "25120311574027200",
  "error_id": "makepkg.eid.kernel/sched/fair.c:error:invalid-use-of-undefined-type'struct-task_group'",
  "bisect_status": "wait",
  "category": "build",
  "git_url": "git://172.168.131.113:9418/new-upstream/l/linux/openeuler-kernel.git",
  "submit_time": 1765788194,
  "priority_level": 999
}
```

#### 阶段 2：任务执行（processing）

Consumer 获取任务并执行 bisect：

```json
{
  "bisect_status": "processing",
  "start_time": 1765788500,
  "retry_count": 0
}
```

#### 阶段 3：任务完成（success）

Bisect 完成，找到 first_bad_commit：

```json
{
  "_id": 1670598882725646785,
  "bad_job_id": "25120311574027200",
  "error_id": "makepkg.eid.kernel/sched/fair.c:error:invalid-use-of-undefined-type'struct-task_group'",
  "bisect_status": "success",
  "category": "build",
  "git_url": "git://172.168.131.113:9418/new-upstream/l/linux/openeuler-kernel.git",
  "first_bad_commit": "433c0b72564239cf3086f563d5ca32a10e4ffd3f",
  "first_bad_id": "25121112063620900",
  "first_result_root": "/result/makepkg/2025-12-11/dc-16g/openeuler-24.03-aarch64/...",
  "submit_time": 1765788194,
  "updated_at": 1765789281,
  "j": {
    "verification_status": "verified",
    "verified_at": 1765789281,
    "introduced_errids": [
      "makepkg.eid.kernel/sched/fair.c:error:invalid-use-of-undefined-type'struct-task_group'",
      "stderr.eid.kernel/sched/fair.c:#:#:error:invalid_use_of_undefined_type'struct_task_group'",
      "stderr.msg.kernel/sched/fair.c:#:#:error:invalid_use_of_undefined_type'struct_task_group'.message",
      "stderr.msg.kernel/sched/fair.c:#:#:error:implicit_declaration_of_function'is_tg_steal'[-Werror=implicit-function-declaration].message",
      "stderr.eid.kernel/sched/fair.c:#:#:error:implicit_declaration_of_function'is_tg_steal'[-Werror=implicit-function-declaration]",
      "makepkg.eid.kernel/sched/fair.c:error:implicit-declaration-of-function'is_tg_steal'[-Werror=implicit-function-declaration]"
    ],
    "parent_job_id": "25121112063150400",
    "candidate_job_id": "25121112063620900",
    "verification_method": "batch_async_validation",
    "job_request_count": 2,
    "is_result_reused": true,
    "job_reused_rate": 1,
    "verification_jobs": {
      "status": "completed",
      "completed_at": 1765789281
    }
  }
}
```

#### 字段说明

| 字段 | 说明 |
|-----|------|
| `first_bad_commit` | 引入问题的第一个坏提交 |
| `first_bad_id` | 验证 first_bad_commit 的 job_id |
| `introduced_errids` | 该 commit 引入的所有错误 ID 列表 |
| `verification_status` | 验证状态（pending/verified） |
| `is_result_reused` | 是否复用了其他任务的结果 |
| `parent_job_id` | 验证用的父提交 job_id |
| `candidate_job_id` | 验证用的候选提交 job_id |

### 7.3 Bisect 报告案例

以下是典型的 bisect 结果报告：

```
tree:   git://172.168.131.113:9418/new-upstream/l/linux/openeuler-kernel.git master
commit: 5c9754d56876f60e199456beda45715da2d1a20b mm/mem_sampling: Add eBPF interface for memory access tracing

================================================================================
Bisect Report - 20251212
================================================================================

Task ID:     5334198313100531946
Bad Job ID:  25112120174278100

Test Suite:  makepkg
Architecture: aarch64

Error ID:
makepkg.eid../include/trace/perf.h:error:conflicting-types-for'perf_trace_mm_spe_record';have'void(v...

First Bad Commit:
5c9754d56876f60e199456beda45715da2d1a20b mm/mem_sampling: Add eBPF interface for memory access tracing

Introduced Error IDs (28 total):
--------------------------------------------------------------------------------
1. makepkg.eid../include/trace/events/kmem.h:error:passing-argument#of'do_trace_eve...
2. stderr.msg../include/trace/events/kmem.h:#:#:error:passing_argument#of'__traceit...
3. stderr.eid../include/trace/events/kmem.h:#:#:error:passing_argument#of'trace_eve...
4. stderr.msg../include/trace/perf.h:#:#:error:passing_argument#of'check_trace_call...
5. makepkg.eid../include/linux/static_call_types.h:error:conflicting-types-for'__SC...
6. stderr.eid../include/trace/perf.h:#:#:error:passing_argument#of'check_trace_call...
7. makepkg.eid../include/linux/tracepoint.h:error:conflicting-types-for'__traceiter...
8. makepkg.eid../include/trace/events/kmem.h:error:invalid-use-of-undefined-type'st...
9. stderr.msg../include/trace/trace_events.h:#:#:error:'perf_trace_mm_spe_record'us...
10. stderr.eid../include/trace/events/kmem.h:#:#:error:passing_argument#of'__traceit...

... and 18 more error(s)

================================================================================
Repository Information
================================================================================
Git URL:     git://172.168.131.113:9418/new-upstream/l/linux/openeuler-kernel.git
Branch:      master
Bad Commit:  5c9754d56876f60e199456beda45715da2d1a20b mm/mem_sampling: Add eBPF interface for memory access tracing
```

**报告字段说明**：

| 字段 | 说明 |
|-----|------|
| Task ID | Bisect 任务的唯一标识 |
| Bad Job ID | 触发 bisect 的失败作业 ID |
| Test Suite | 测试套件名称（makepkg = 构建测试） |
| Architecture | 测试架构 |
| Error ID | 触发 bisect 的主要错误 ID |
| First Bad Commit | 定位到的第一个坏提交 |
| Introduced Error IDs | 该提交引入的所有错误列表 |

---

## 8. 运维操作

### 8.1 日常监控

#### 常用查询命令

```bash
# 查看失败的构建任务及其最后错误信息
python3 $CCI_SRC/sbin/bisect_api.py list_tasks --status failed --category build | grep last

# 查看失败的功能测试任务
python3 $CCI_SRC/sbin/bisect_api.py list_tasks --status failed --category function | grep last

# 查看失败的性能测试任务
python3 $CCI_SRC/sbin/bisect_api.py list_tasks --status failed --category benchmark | grep last

# 手动创建性能 bisect 任务（指定 good commit）
python3 $CCI_SRC/sbin/bisect_api.py new_task --metric "unixbench.Pipe_Throughput" \
    --bad_job_id 25121117334606400 --good_commit a13c2631d4e1

# 手动创建错误 bisect 任务（指定 good commit）
python3 $CCI_SRC/sbin/bisect_api.py new_task --error_id "makepkg.eid.kernel/xxx.c:error" \
    --bad_job_id 25121117334606400 --good_commit a13c2631d4e1
```

#### 查看 Producer 状态

```bash
# 查看最新状态
cat /srv/result/bisect/producer_stats/producer_latest.txt

# 查看今天的详细报告
TODAY=$(date +%Y-%m-%d)
cat /srv/result/bisect/producer_stats/$TODAY/producer_report_*.txt

# 查看筛选汇总
ls -t /srv/result/bisect/logs/analysis/summary_*.txt | head -1 | xargs cat
```

#### 查看任务统计

```bash
# 各状态任务数量
python3 sbin/bisect_api.py list_tasks --status wait --limit 1
python3 sbin/bisect_api.py list_tasks --status processing --limit 1
python3 sbin/bisect_api.py list_tasks --status success --limit 1
python3 sbin/bisect_api.py list_tasks --status failed --limit 1

# 最近 24 小时的任务
python3 sbin/bisect_api.py list_tasks --hours 24
```

#### 查看系统健康状态

```bash
# 线程池状态
python3 sbin/bisect_api.py thread_status

# 仓库池状态
python3 sbin/bisect_api.py pool_status
python3 sbin/bisect_api.py pool_stats
```

### 8.2 故障排查

#### Producer 没有生成报告

```bash
# 1. 检查 producer 是否启用
python3 sbin/bisect_api.py producer_status

# 2. 手动触发一次
python3 sbin/bisect_api.py trigger_producer --force

# 3. 检查最新运行时间
cat /srv/result/bisect/producer_stats/producer_latest.txt
```

#### 任务长时间处于 processing

```bash
# 1. 查看 processing 任务
python3 sbin/bisect_api.py list_tasks --status processing

# 2. 检查线程池状态
python3 sbin/bisect_api.py thread_status

# 3. 重置卡住的任务
python3 sbin/bisect_api.py reset_processing
```

#### 仓库克隆超时

```bash
# 1. 检查网络连接
ping gitee.com

# 2. 查看仓库池状态
python3 sbin/bisect_api.py pool_status

# 3. 清理问题实例
python3 sbin/bisect_api.py pool_cleanup --execute
```

### 8.3 状态重置操作

```bash
# 重置失败任务（重新尝试）
python3 sbin/bisect_api.py reset_failed

# 重置处理中任务（处理卡住的任务）
python3 sbin/bisect_api.py reset_processing

# 重置验证中任务
python3 sbin/bisect_api.py reset_verifying

# 清理孤立任务
python3 sbin/bisect_api.py cleanup_orphaned_verifying
```

### 8.4 清理与维护

#### 定期清理脚本

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

#### 磁盘空间监控

```bash
# 检查仓库目录空间
df -h /bisect_repos/

# 检查 tmpfs 使用
df -h /tmp

# 触发仓库池清理（预览）
python3 sbin/bisect_api.py pool_cleanup --dry-run

# 执行清理
python3 sbin/bisect_api.py pool_cleanup --execute --max-age-days 0.5
```

---

## 9. 部署指南

本章节介绍如何从零开始部署 Bisect 系统，包括 compass-ci 基础环境和 bisect 容器的部署。

### 9.1 前置条件

#### 系统要求

| 项目 | 要求 |
|-----|------|
| **操作系统** | Linux (推荐 openEuler 22.03+, CentOS 8+, Ubuntu 20.04+) |
| **CPU** | 最低 4 核，推荐 8+ 核 |
| **内存** | 最低 8GB，推荐 16GB+ |
| **磁盘** | 至少 100GB 用于仓库缓存 |
| **Docker** | Docker 20.10+ |
| **Git** | Git 2.30+ |

#### 依赖服务

| 服务 | 用途 | 默认端口 |
|-----|------|---------|
| **Manticore Search** | 数据库存储 bisect 任务 | 9308 |
| **Elasticsearch** | Jobs 数据存储 | 9200 |
| **Git 服务器** | 内核源码仓库 | 9418 |

### 9.2 Compass-CI 基础环境部署

#### 步骤 1：克隆代码仓库

```bash
# 创建工作目录
mkdir -p ~/compass-ci && cd ~/compass-ci

# 克隆必需的仓库
git clone https://gitee.com/compass-ci/lkp-tests.git
git clone https://gitee.com/openeuler/compass-ci.git
```

#### 步骤 2：配置环境变量

```bash
# 编辑 ~/.bashrc 或 ~/.zshrc
export CCI_SRC="$HOME/compass-ci/compass-ci"
export LKP_SRC="$HOME/compass-ci/lkp-tests"
export PATH="$CCI_SRC/sbin:$LKP_SRC/sbin:$PATH"

# 使配置生效
source ~/.bashrc
```

#### 步骤 3：安装 Ruby 和 Crystal 依赖

```bash
# Ruby 依赖
gem install rest-client base64

# Python 依赖
pip3 install requests pyyaml flask flask-cors numpy schedule
```

#### 步骤 4：配置 compass-ci

```bash
# 创建配置目录
mkdir -p /etc/compass-ci/defaults
mkdir -p ~/.config/compass-ci

# 复制默认配置（根据实际环境修改）
cp $CCI_SRC/etc/defaults/*.yaml /etc/compass-ci/defaults/
```

### 9.3 Bisect 容器部署

#### 代码位置

| 文件/目录 | 说明 |
|---------|------|
| `container/bisect/Dockerfile` | Docker 镜像构建文件 |
| `container/bisect/build` | 镜像构建脚本 |
| `container/bisect/start` | 容器启动脚本 |
| `container/bisect/config/` | 配置文件目录 |

#### 步骤 1：构建 Docker 镜像

```bash
cd $CCI_SRC

# 使用构建脚本构建镜像
bash container/bisect/build
```

**构建过程说明**：

构建脚本会执行以下操作：
1. 基于 Alpine 镜像创建轻量级容器
2. 安装 Python3, Ruby, Git 等依赖
3. 复制 compass-ci 和 lkp-tests 代码到容器
4. 配置 bisect 用户和工作目录

#### 步骤 2：准备存储目录

```bash
# 创建必需的目录
sudo mkdir -p /srv/result        # 结果存储
sudo mkdir -p /srv/cache         # 通用缓存
sudo mkdir -p /srv/log/kernel_ci # Kernel CI 日志
sudo mkdir -p /srv/git/auto_test_repos  # 自动测试仓库
sudo mkdir -p /tmp               # 工作目录（默认映射到 /c/bisect）

# 设置权限
sudo chown -R $(id -u):$(id -g) /srv/result
```

#### 步骤 3：配置启动参数

编辑 `container/bisect/start` 脚本，根据实际环境修改以下配置：

```ruby
# 数据库配置
MANTICORE_HOST='172.17.0.1'  # Manticore 数据库地址（Docker 网关）

# 工作目录配置
HOST_WORK_DIR='/tmp/'              # 主机工作目录
HOST_RESULT_DIR='/srv/result'      # 主机结果目录

# 性能配置
BISECT_THREADS=64                  # 并发线程数（根据 CPU 核数调整）
```

#### 步骤 3.1：容器服务切换运行账号时需要修改的项

如果要把容器内运行用户从默认 `bisect` 改成其它账号，至少要同步修改以下位置（缺一可能导致启动失败或无权限写日志/结果）：

1. `container/bisect/Dockerfile`
   - `addgroup/adduser` 的 UID/GID
   - `USER bisect`（改为新用户）
2. `container/bisect/config/supervisord.conf`
   - `[supervisord] user=...`
   - 各 `[program:*] user=...`
3. `container/bisect/start`
   - `DEFAULT_BISECT_CONFIG_DIR='/home/bisect/.config/compass-ci/'`（若新用户 home 不同，需改路径）
   - 挂载路径与新 home 对齐（`-v ~/.config/compass-ci:/home/<new-user>/.config/compass-ci`，建议可写）
4. 宿主机目录权限
   - 至少保证新 UID/GID 对以下挂载目录可写：`/srv/result`、`/tmp`（对应 `HOST_WORK_DIR`）、`/srv/cache`、`/srv/log/kernel_ci`、`/srv/git/auto_test_repos`

建议验证：

```bash
docker exec -it bisect id
docker exec -it bisect sh -lc 'touch /result/bisect/logs/api/.perm_check && rm -f /result/bisect/logs/api/.perm_check'
```

#### 步骤 3.2：Kernel-CI 配置文件映射（宿主机配置）

当前启动脚本通过环境变量将容器内配置目录固定为：

- `KERNEL_CI_CONFIG_DIR=/result/bisect/kernel_ci_config`

并通过卷映射：

- 宿主机 `HOST_RESULT_DIR`（默认 `/srv/result`）挂载到容器 `/result`

所以宿主机实际目录是：

- `/srv/result/bisect/kernel_ci_config`

在宿主机准备并放置配置文件：

```bash
mkdir -p /srv/result/bisect/kernel_ci_config
# 例如放置 kernel-ci 相关 YAML 配置
cp /path/to/your/kernel-ci/*.yaml /srv/result/bisect/kernel_ci_config/
```

容器内验证：

```bash
docker exec -it bisect ls -la /result/bisect/kernel_ci_config
```

另外，基础 compass-ci 配置映射仍然来自：
- `/etc/compass-ci/defaults` -> `/etc/compass-ci/defaults`（只读）
- `~/.config/compass-ci` -> `/home/bisect/.config/compass-ci`（读写；切换运行账号时需同步调整）

说明：用户配置目录建议读写挂载。只读挂载在部分场景下会导致提交/认证相关流程无法更新本地用户配置。

#### 步骤 4：启动容器

```bash
cd $CCI_SRC

# 启动 bisect 容器
ruby container/bisect/start
```

**启动脚本关键配置**：

```ruby
# 容器启动参数说明
docker run
  --name bisect                    # 容器名称
  --restart=always                 # 自动重启策略
  -e MANTICORE_HOST=172.17.0.1     # 数据库地址
  -e BISECT_PRODUCER_ENABLED=true  # 启用自动任务发现
  -e BISECT_THREADS=64             # 并发执行线程数
  -e LOG_LEVEL=DEBUG               # 日志级别
  -e KERNEL_CI_CONFIG_DIR=/result/bisect/kernel_ci_config
  -v /srv/result:/result/          # 结果目录挂载
  -v /tmp:/c/bisect                # 工作目录挂载
  -v /srv/cache:/srv/cache         # 缓存目录挂载
  -v /srv/log/kernel_ci:/srv/log/kernel_ci
  -v /srv/git/auto_test_repos:/srv/git/auto_test_repos
  -p 9999:9999                     # API 端口
  -p 8765:8765                     # Commit Time Service 端口
  bisect                           # 镜像名称
```

#### 步骤 5：验证部署

```bash
# 检查容器状态
docker ps | grep bisect

# 查看容器日志
docker logs -f bisect

# 验证 API 服务
curl http://localhost:9999/health

# 验证 Producer 状态
python3 $CCI_SRC/sbin/bisect_api.py producer_status

# 查看线程池状态
python3 $CCI_SRC/sbin/bisect_api.py thread_status
```

### 9.4 配置文件说明

#### supervisord.conf

位置：`container/bisect/config/supervisord.conf`

管理容器内的多个进程：
- Flask API Server (端口 9999)
- Bisect Consumer
- Verification Consumer
- Producer (可选)
- Commit Time Service (端口 8765)

#### errid_filters.yaml

位置：`container/bisect/config/errid_filters.yaml`

配置 error_id 筛选规则：
- 环境错误黑名单
- 高价值错误白名单
- 优先级评分规则

```yaml
# 示例配置
priority_scoring:
  has_file_path: 30      # 包含文件路径加分
  critical_level: 40     # 严重错误加分
  high_level: 25         # 高级别错误加分
  code_related: 20       # 代码相关加分

default_parameters:
  max_count: 6           # 每个 job 最多处理的 error_id 数量
  min_priority: 35       # 最低优先级阈值
```

### 9.5 网络架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        部署架构图                                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Git Server    │     │   Manticore     │     │  Elasticsearch  │
│   :9418         │     │   :9308         │     │   :9200         │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                        ┌────────┴────────┐
                        │  Docker Network │
                        │  (172.17.0.0/16)│
                        └────────┬────────┘
                                 │
                        ┌────────┴────────┐
                        │  Bisect Container│
                        │  :9999 (API)     │
                        │  :8765 (Commit)  │
                        └─────────────────┘
```

### 9.6 常见部署问题

#### 问题 1：容器无法连接 Manticore

**症状**：容器启动后立即退出

**解决方案**：
```bash
# 检查 Manticore 是否运行
docker ps | grep manticore

# 确认网络连通性
docker exec bisect ping 172.17.0.1

# 检查端口是否开放
docker exec bisect nc -zv 172.17.0.1 9308
```

#### 问题 2：Git 仓库克隆失败

**症状**：任务一直处于 processing 状态

**解决方案**：
```bash
# 检查 Git 服务连通性
git ls-remote git://your-server:9418/linux.git

# 增加克隆超时
# 编辑 start 脚本，添加环境变量
-e GIT_CLONE_PRISTINE_TIMEOUT=14400
```

#### 问题 3：磁盘空间不足

**症状**："No space left on device" 错误

**解决方案**：
```bash
# 清理仓库缓存
docker exec bisect rm -rf /srv/git/bisect_repos/workspaces/*

# 清理旧日志
find /srv/result/bisect -name "*.log" -mtime +30 -delete

# 执行仓库池清理
python3 $CCI_SRC/sbin/bisect_api.py pool_cleanup --execute
```

### 9.7 升级指南

#### 升级步骤

```bash
# 1. 拉取最新代码
cd $CCI_SRC
git pull origin master

# 2. 重新构建镜像
bash container/bisect/build

# 3. 停止当前容器
docker stop bisect

# 4. 删除旧容器
docker rm bisect

# 5. 启动新容器
ruby container/bisect/start

# 6. 验证升级成功
python3 $CCI_SRC/sbin/bisect_api.py thread_status
```

#### 数据迁移

Bisect 任务数据存储在 Manticore 数据库中，升级容器不会影响已有数据。如需迁移数据库，请参考 Manticore 官方文档。

---

## 附录

### A. 环境变量参考

| 变量名 | 默认值 | 说明 |
|-------|-------|------|
| `BISECT_API_HOST` | localhost:9999 | API 服务器地址 |
| `BISECT_THREADS` | 32 | 并发执行线程数 |
| `BISECT_MAX_CONCURRENT_CLONES` | 4 | 最大并发克隆数 |
| `BISECT_PRODUCER_ENABLED` | true | 启用 Producer |
| `PARALLEL_VERIFICATION_JOBS` | 200 | 并行验证作业数 |
| `VERIFICATION_BATCH_SIZE` | 200 | 验证批量大小 |
| `REPO_POOL_MAX_INSTANCES` | 64 | 每仓库最大实例数 |
| `REPO_POOL_ACQUIRE_TIMEOUT` | 28800 | 获取实例超时（秒） |

### B. 相关文档

- [设计文档](container/bisect/docs/DESIGN.md) - 系统架构和设计原理
- [API 文档](container/bisect/docs/API_DOCUMENTATION.md) - API 接口详细说明
- [用户指南](container/bisect/docs/USER_GUIDE.md) - 详细使用指南

---

**文档版本**: 1.1
**最后更新**: 2025-12-23
**维护者**: Bisect Team
