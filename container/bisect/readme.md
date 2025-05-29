# Bisect 任务管理

## 概述

`bisect_task` 是一个用于自动化处理 bisect 任务的服务。它通过与 Manticore 数据库交互，管理任务的提交、处理和状态更新。

### bisect-task 流程

+---------+  get_new_bisect_task_from_jobs   +-----------------+  add_bisect_task   +-----------------------------+
| jobs db | -------------------------------> | bisect producer | -----------------> |          bisect db          |
+---------+                                  +-----------------+                    +-----------------------------+
                                                                                      |
                                                                                      | get_tasks_from_bisect_task
                                                                                      v
                                                                                    +-----------------------------+     +-----------+          +-------------------+
                                                                                    |       bisect consumer       | --> | run bisct | -+-----> | bisect process .. |
                                                                                    +-----------------------------+     +-----------+  |       +-------------------+
                                                                                                                                       |       +-------------------+
                                                                                                                                       +-----> | bisect process 1  |
                                                                                                                                       |       +-------------------+
                                                                                                                                       |       +-------------------+
                                                                                                                                       +-----> | bisect process n  |
                                                                                                                                               +-------------------+
### 在 compass-ci 中

+-----------------+          +------------+           +-------------------------+
| upstream update | -+-----> | benchmark  | ------+-> |         jobs db         |
+-----------------+  |       +------------+       |   +-------------------------+
                     |                            |     |
                     |                            |     | bad_job
                     |                            |     v
                     |       +------------+       |   +-------------------------+                            valid errid
                     +-----> |   build    | ------+   |  bisect-task producer   | <---------------------------------------------------+
                     |       +------------+       |   +-------------------------+                                                     |
                     |                            |     |                                                                             |
                     |                            |     |                                                                             |
                     |                            |     v                                                                             |
                     |       +------------+       |   +-------------------------+                                                     |
                     +-----> | functional | ------+   |        bisect db        | <+                                                  |
                             +------------+           +-------------------------+  |                                                  |
                                                        |                          |                                                  |
                                                        | task wait to be bisect   | found first bad commit                           |
                                                        v                          |                                                  |
                                                      +----------------------------------------------------+  sucess bisect errid   +---------------+
                                                      |                bisect-task consumer                | ---------------------> | regression db |
                                                      +----------------------------------------------------+                        +---------------+
                                                        |                          ^
                                                        | task                     | return result
                                                        v                          |
                                                      +-------------------------+  |
                                                      |        bisect-py        | -+
                                                      +-------------------------+
## 功能

- **任务提交**：通过 API 接口提交新的 bisect 任务。
- **任务处理**：自动从数据库中获取待处理任务，并执行 bisect 操作。
- **状态更新**：实时更新任务状态，并将结果存储到数据库中。
- **回归检查**：更新回归数据库以记录任务的执行结果。

## 数据库设计

### Bisect 表结构

`bisect` 表用于存储所有的 bisect 任务信息。其结构如下：

- **`id`**: `bigint`，任务的唯一标识符。
- **`bad_job_id`**: `string`，标记为不良的作业ID。
- **`error_id`**: `string`，任务相关的错误标识符。
- **`bisect_status`**: `string`，任务的当前状态（如 `wait`、`processing`、`completed`、`failed`）。
- **其他字段**：用于存储任务的详细信息。

### 回归检查表结构

`regression` 表用于存储回归检查的结果。其结构如下：

- **`id`**: `bigint`，唯一标识符。
- **`record_type`**: `string`，记录类型，通常为 `errid`。
- **`errid`**: `string`，错误标识符。
- **`category`**: `string`，错误类别。
- **其他字段**：用于存储回归检查的详细信息。

## 任务处理流程

### 生产者流程

- **任务发现**：定期从 `jobs` 数据库中获取新的故障任务。
- **任务过滤**：根据错误标识符的白名单过滤任务。
- **任务提交**：将符合条件的任务提交到 `bisect` 数据库。

### 消费者流程

- **任务获取**：从 `bisect` 数据库中获取状态为 `wait` 的任务。
- **任务执行**：执行 bisect 操作以查找故障提交。
- **结果更新**：更新任务状态为 `completed` 或 `failed`，并记录结果。
- **回归检查**：更新 `regression` 数据库以记录任务的执行结果。

## 历史设计讨论

### Bisect 提交

#### 方式1:
- 在特定测试机上运行
- 确保安全性：账户/令牌，访问服务

#### 方式2:
- 提交 job1
- 提交 job2，重用相同的账户信息
- 问题：消耗信用/机器时间

#### 方式3:
- compass ci 容器运行为服务
- 参考 delimiter 服务
- 提供 API/new-bisect-task，添加到 ES
- 循环：从 ES 消费一个任务，fork 进程，开始 bisect

### 回归数据库
### Bisect 任务队列
### Bisect 任务管理和仪表板

- Bisect 任务名称
- 套件，开始时间/运行时间，步骤，组ID

## bisect submit 归档设计部分

### way1:
	run in special testbox

ensure security:
- account/token
- visit services


common testbox:
	submit upload lkp-tests tar ball, run in testbox

secure testbox:
	submit NO UPLOAD lkp-tests tar ball
	run only selected list of programs
	run in a dedicated host machine, FW can visit services


### way2:
submit job1
	submit job2, reuse same account info
problem: consumes his credit / machine time

### way3:
compass ci container/ run as service
refer to delimiter service
	system bisect account

	provide API/new-bisect-task
		add to ES
	
	loop:
		consume one task from ES
		fork process, start bisect
			bisect step
			submit job
			change bisect-task state=finish

submit-jobs

### regression db
### bisect task queue
### bisect tasks management and dashboard

	bisect task name	
	suite	start_time/run_time  step group_id

## 附录

### 流程图源码

```
##############################################################
# compass-ci bisect 流程图 v 0.5

[ upstream update ] -> { start: front, 0; }  [ build ], [ functional ],  [ benchmark ] -> { end: back,0; } [ jobs db ]
[ jobs db ]  {flow: south;} - bad_job  -> [ bisect-task producer ] -> {flow: south;} [ bisect db ] {flow: south;} - task wait to be bisect -> [ bisect-task consumer ] - task -> [ bisect-py ]
[ bisect-py ] - return result -> [ bisect-task consumer ] - found first bad commit -> [ bisect db ]
[ regression db ] - valid errid -> [ bisect-task producer ]
[ bisect-task consumer ] - sucess bisect errid ->  [ regression db ]
```

```
##############################################################
# bisect-task 流程图 v 0.5
# {flow: south;} 向下
# { end: back,0; } 多个聚合为一
# { start: front, 0; } 一分为多
[ jobs db ] - get_new_bisect_task_from_jobs -> [ bisect producer ] - add_bisect_task -> [ bisect db ]
[ bisect db ] - get_tasks_from_bisect_task -> {flow: south;} [ bisect consumer ] -> [ run bisct ]
[ run bisct ] -> { start: front, 0; } [ bisect process 1 ], [ bisect process .. ], [ bisect process n ]
```

