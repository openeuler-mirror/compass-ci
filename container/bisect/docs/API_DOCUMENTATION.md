# Bisect API 文档

## 概述

Bisect API 提供了完整的任务管理接口，支持错误类型和性能类型的二分查找任务。系统提供了 Python 客户端脚本 `bisect_api.py`，支持彩色输出和自动 URL 编码，较直接使用 `curl` 更方便。

## 快速开始

### 安装依赖
```bash
pip3 install requests
```

### 设置环境变量（可选）
```bash
export BISECT_API_HOST="localhost:9999"  # 默认值
```

### 使用 bisect_api.py 客户端

```bash
# 查看帮助
python3 sbin/bisect_api.py -h

# 查看具体命令帮助
python3 sbin/bisect_api.py new_task -h
python3 sbin/bisect_api.py list_tasks -h
```

## 接口概览

| 端点 | 方法 | 功能 | 客户端命令 |
|------|------|------|------------|
| `/api/v1/new_bisect_task` | POST | 创建新的 bisect 任务 | `new_task` |
| `/api/v1/list_bisect_tasks` | GET | 获取任务列表 | `list_tasks` |
| `/api/v1/delete_tasks` | DELETE | 根据条件删除任务 | `delete_tasks` |
| `/api/v1/reset_failed_tasks` | POST | 重置失败任务 | `reset_failed` |
| `/api/v1/reset_processing_tasks` | POST | 重置 processing 任务 | `reset_processing` |
| `/api/v1/thread_pool_status` | GET | 获取线程池状态 | `thread_status` |
| `/api/v1/verification_status` | GET | 获取验证队列和超时恢复状态 | `verification_status` |
| `/api/v1/status_overview` | GET | 获取精确任务状态统计（供 `status` 汇总视图使用） | `status` |
| `/api/v1/toggle_producer` | POST | 切换生产者状态 | `enable_producer`/`disable_producer` |
| `/api/v1/producer_status` | GET | 获取生产者状态 | `producer_status` |
| `/api/v1/trigger_producer_run` | POST | 手动触发生产者 | `trigger_producer` |
| `/api/v1/toggle_consumer` | POST | 切换消费者状态（BisectConsumer + SuccessTaskValidator） | `enable_consumer`/`disable_consumer` |
| `/api/v1/consumer_status` | GET | 获取消费者状态 | `consumer_status` |
| `/api/v1/pool/status` | GET | 获取仓库池状态 | `pool_status` |
| `/api/v1/pool/cleanup` | POST | 触发仓库池清理 | `pool_cleanup` |
| `/api/v1/pool/stats` | GET | 获取池监控统计 | `pool_stats` |
| `/api/v1/pool/verify` | POST | 验证池一致性 | `pool_verify` |
| `/api/v1/pool/monitor/start` | POST | 启动池监控线程 | `pool_monitor_start` |
| `/api/v1/pool/monitor/stop` | POST | 停止池监控线程 | `pool_monitor_stop` |

## 详细接口说明

### 1. 创建 bisect 任务

**客户端命令**: `new_task`

**支持的任务类型**:
- **错误类型任务**: 基于错误 ID 进行二分查找
- **性能类型任务**: 基于性能指标进行二分查找

**使用示例**:
```bash
# 错误类型任务
python3 sbin/bisect_api.py new_task --bad_job_id 123456 --error_id "compile_error"

# 性能类型任务
python3 sbin/bisect_api.py new_task --bad_job_id 123456 --metric "hackbench.throughput"

# 从JSON文件创建
python3 sbin/bisect_api.py new_task -f task.json

# 直接传入JSON字符串
python3 sbin/bisect_api.py new_task -j '{"bad_job_id":"123456","error_id":"test.error"}'

# 指定 Git 仓库 URL
python3 sbin/bisect_api.py new_task --bad_job_id 123456 --error_id "test.error" --git_url "https://github.com/torvalds/linux.git"
```

**任务数据结构**:
```json
{
  "bad_job_id": "25102209094235200",
  "error_id": "stderr.compilation_error:undefined_reference",
  "git_url": "https://github.com/torvalds/linux.git",
  "good_commit": "abc123..."  // 可选，已知的好提交（将保存到 j.good_commit 字段）
}
```

**注意**: `good_commit` 参数会被自动保存到数据库的 `j` 字段中（因为表结构没有独立的 `good_commit` 列）。

### 2. 查询任务列表

**客户端命令**: `list_tasks`

**支持的筛选条件**:
- `--status`: 按任务状态筛选 (`wait`/`processing`/`success`/`failed`)
- `--error_id`: 按完整错误 ID 精确筛选（支持特殊字符自动编码）
- `--bad_job_id`: 按 bad_job_id 筛选
- `--limit`: 限制返回数量

**使用示例**:
```bash
# 查询所有任务
python3 sbin/bisect_api.py list_tasks

# 按状态筛选
python3 sbin/bisect_api.py list_tasks --status success
python3 sbin/bisect_api.py list_tasks --status failed

# 按完整 error_id 精确筛选（支持特殊字符）
python3 sbin/bisect_api.py list_tasks --error_id "stderr.eid.fs/#p/vfs_file.c:warning"
python3 sbin/bisect_api.py list_tasks --error_id "makepkg.eid.fs/#p/vfs_file.c:warning:Excess-function-parameter"

# 组合筛选
python3 sbin/bisect_api.py list_tasks --status wait --error_id "test.error" --limit 10
python3 sbin/bisect_api.py list_tasks --bad_job_id 12345 --status success
```

**说明**:
- `--error_id` 为精确匹配，不做子串匹配
- 如果只传入 `linux/compiler_types.h` 这类片段，通常不会命中；应传入完整 `error_id`

**响应格式**:
```json
{
  "tasks": [
    {
      "id": 12345,
      "bad_job_id": "25102209094235200",
      "error_id": "stderr.compilation_error:undefined_reference",
      "bisect_status": "success",
      "first_bad_commit": "a1b2c3d4e5f6...",
      "git_url": "https://github.com/torvalds/linux.git",
      "category": "build",
      "direction": "",
      "j": {
        "verification_status": "verified",
        "introduced_errids": ["stderr.compilation_error:undefined_reference"]
      }
    }
  ]
}
```

### 3. 删除任务

**客户端命令**: `delete_tasks`

**支持的删除条件**:
- `--id`: 按任务ID删除
- `--error_id`: 按完整错误 ID 删除
- `--bad_job_id`: 按 bad_job_id 删除
- `--git_url`: 按 Git 仓库 URL 删除

**使用示例**:
```bash
# 按ID删除
python3 sbin/bisect_api.py delete_tasks --id 1001

# 按完整 error_id 删除
python3 sbin/bisect_api.py delete_tasks --error_id "test.error"

# 按 bad_job_id 删除
python3 sbin/bisect_api.py delete_tasks --bad_job_id 12345

# 组合条件删除（AND关系）
python3 sbin/bisect_api.py delete_tasks --error_id "test.error" --bad_job_id 12345

# 非交互环境跳过确认
python3 sbin/bisect_api.py delete_tasks --id 1001 --yes
```

**注意**:
- 删除操作默认会要求确认，不可恢复，请谨慎使用
- 在脚本、CI 或 pipe 环境中，请加 `--yes` 或 `-y`

### 4. 重置任务状态

**客户端命令**: `reset_failed`, `reset_processing`

**功能说明**:
- `reset_failed`: 将所有失败状态的任务重置为 `wait` 状态
- `reset_processing`: 将所有 `processing` 状态的任务重置为 `wait` 状态

**使用示例**:
```bash
# 重置失败任务
python3 sbin/bisect_api.py reset_failed

# 重置 processing 任务
python3 sbin/bisect_api.py reset_processing

# 非交互环境跳过确认
python3 sbin/bisect_api.py reset_failed --yes
```

### 5. 线程池状态

**客户端命令**: `thread_status`

**使用示例**:
```bash
python3 sbin/bisect_api.py thread_status
```

**响应格式**:
```json
{
  "max_workers": 16,
  "active_threads": 3,
  "pending_tasks": 5,
  "completed_tasks": 100,
  "verification": {
    "pending_verification": 8,
    "verifying": 4,
    "active_submitted_verifying": 4,
    "available_verifying_slots": 6
  }
}
```

### 6. 验证队列状态

用于观测复用验证的排队压力、超时恢复情况以及当前配额。

**使用示例**:
```bash
curl -s http://localhost:9999/api/v1/verification_status | jq .
python3 sbin/bisect_api.py verification_status
```

**响应格式**:
```json
{
  "pending_verification": 12,
  "verifying": 5,
  "active_submitted_verifying": 5,
  "available_verifying_slots": 5,
  "verification_status_counts": {
    "verified": 320,
    "timeout_retry_pending": 3,
    "timeout": 7,
    "timeout_unverified": 0
  },
  "config": {
    "max_verifying_tasks": 10,
    "verification_timeout_hours": 24,
    "verification_timeout_retry_max": 2,
    "verification_timeout_final_action": "rebisect"
  }
}
```

### 7. 生产者控制

**客户端命令**: `enable_producer`, `disable_producer`, `producer_status`, `trigger_producer`

**功能说明**:
- `enable_producer`: 启用后台生产者任务
- `disable_producer`: 禁用后台生产者任务
- `producer_status`: 获取生产者运行状态
- `trigger_producer`: 手动触发一次生产者运行

**使用示例**:
```bash
# 启用生产者
python3 sbin/bisect_api.py enable_producer

# 禁用生产者
python3 sbin/bisect_api.py disable_producer

# 查看生产者状态
python3 sbin/bisect_api.py producer_status

# 手动触发生产者运行
python3 sbin/bisect_api.py trigger_producer
```

### 8. 系统总览

**客户端命令**: `status`

**功能说明**:
- 使用 `/api/v1/status_overview` 返回的精确计数展示各任务状态总量
- 同屏拼接 `verification_status`、`thread_pool_status`、`producer_status`、`consumer_status`
- `pending_verification` 会按完整状态名展示，不再误写为 `pending`

**使用示例**:
```bash
python3 sbin/bisect_api.py status
```

### 9. 消费者控制

**客户端命令**: `enable_consumer`, `disable_consumer`, `consumer_status`

**功能说明**:
- `enable_consumer`: 启用 BisectConsumer + SuccessTaskValidator
- `disable_consumer`: 禁用 BisectConsumer + SuccessTaskValidator
- `consumer_status`: 获取消费者运行状态

**语义**:
- 关闭开关后 BisectConsumer 不再从 `wait` 队列捞新任务，SuccessTaskValidator 不再提交新的验证 job。
- 已经在 thread pool 里运行的任务会正常跑完，不会被取消。
- 已经提交出去的 verification job 仍会继续轮询和回收结果，不会因为关闭消费开关而卡死。
- 再次启用时 BisectConsumer 和 SuccessTaskValidator 都会被立即唤醒，重新评估开关状态。
- 如果配置了 `BISECT_CONSUMER_STARTUP_DELAY_SECONDS`，容器刚启动时会先进入延迟窗口；此时即使默认是 enabled，也会等延迟结束后才开始捞新任务 / 提交新验证 job。
- HeadValidator 有自己的开关（`BISECT_HEAD_VALIDATOR_ENABLED`），不受这个开关影响。

**使用示例**:
```bash
# 启用消费者
python3 sbin/bisect_api.py enable_consumer

# 禁用消费者
python3 sbin/bisect_api.py disable_consumer

# 查看消费者状态
python3 sbin/bisect_api.py consumer_status
```

## 高级功能

### 自动 URL 编码

客户端自动处理特殊字符的 URL 编码，支持包含 `#`、`&`、空格等特殊字符的完整 `error_id`：

```bash
# 自动处理特殊字符
python3 sbin/bisect_api.py list_tasks --error_id "stderr.eid.fs/#p/vfs_file.c:warning"
python3 sbin/bisect_api.py list_tasks --error_id "makepkg.eid.fs/#p/vfs_file.c:warning:Excess-function-parameter"
```

### 彩色输出

客户端提供彩色输出，便于区分请求、响应和错误信息：
- **蓝色**: 请求信息
- **绿色**: 成功响应
- **红色**: 错误信息
- **黄色**: 警告信息

### 任务排序

查询任务列表时，客户端会自动将 `id` 字段放在最前面，便于查看：
```json
{
  "tasks": [
    {
      "id": 12345,  // 始终在最前面
      "bad_job_id": "25102209094235200",
      "error_id": "stderr.compilation_error:undefined_reference",
      // ... 其他字段
    }
  ]
}
```

## 环境变量

- `BISECT_API_HOST`: API服务器地址，默认为 `localhost:9999`

## 错误处理

所有接口在出错时返回统一格式：
```json
{
  "code": 400/500,
  "data": null,
  "message": "错误描述信息"
}
```

客户端会显示详细的错误信息，包括：
- 连接错误
- 超时错误
- 服务器返回的错误信息

## 最佳实践

### 1. 任务创建
- 优先使用 JSON 文件创建复杂任务
- 对于包含特殊字符的 error_id，直接使用客户端，无需手动编码
- 性能任务需要指定 `bisect_metric` 字段

### 2. 任务查询
- 使用 `--limit` 参数限制返回数量，避免数据过大
- 组合使用筛选条件提高查询效率
- `--error_id` 为精确匹配，应传入完整 `error_id`
- 利用彩色输出快速识别任务状态

### 3. 任务管理
- 定期清理失败任务，释放系统资源
- 监控线程池状态，确保系统正常运行
- 合理控制生产者状态，平衡任务产生和处理

### 4. 监控建议
- 定期检查生产者状态
- 监控线程池活跃线程数
- 关注任务队列长度

## 故障排除

### 连接失败
```bash
# 检查服务是否运行
python3 sbin/bisect_api.py list_tasks

# 如果连接失败，检查环境变量
echo $BISECT_API_HOST
```

### 参数错误
```bash
# 查看具体命令的帮助
python3 sbin/bisect_api.py new_task -h
python3 sbin/bisect_api.py list_tasks -h
```

### 特殊字符处理
客户端自动处理特殊字符，无需手动编码。如果遇到问题，可以：
1. 使用 JSON 文件方式创建任务
2. 检查 error_id 格式是否正确

---

**最后更新**: 2026-03-31
**维护者**: Bisect Team
