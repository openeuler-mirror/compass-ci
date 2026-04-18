# Issue: bisect_api.py CLI 问题清单

## Status: DONE

## 文件位置
- CLI: `sbin/bisect_api.py`
- 路由: `container/bisect/app/routes.py`
- 测试: `container/bisect/app/tests/test_bisect_api_client.py`

## 问题列表

### 1. `reset_failed` 使用 DELETE 方法，语义不一致
- `routes.py:36` 注册为 `methods=['DELETE']`
- 其他 reset 命令（reset_processing, reset_verifying）都用 POST
- reset 语义是"重置状态"不是"删除资源"
- **建议**: 路由改为 POST，client 端已经用 DELETE 需要同步改
- **结果**: 已修复，`routes.py` 和 `bisect_api.py` 已统一为 `POST`

### 2. help 示例中 `--max-hours` 与实际参数 `--max-age-days` 不匹配
- help epilog line 421: `%(prog)s pool_cleanup --max-hours 12`
- 实际 argparse 定义 line 622: `--max-age-days`
- **建议**: help 改为 `pool_cleanup --max-age-days 0.5`
- **结果**: 已修复，CLI 与文档示例已统一为 `--max-age-days`

### 3. `pool_instances` 在 help 中存在但未实现
- help epilog line 424: `%(prog)s pool_instances ltp`
- 无对应 subparser、client 方法或路由
- **建议**: 删除 help 中的 pool_instances 行，或实现该命令
- **结果**: 已修复，CLI 与相关文档中的过期示例已删除

### 4. `list_tasks` 的 `--id` 参数不生效
- `add_common_filter_args` 添加了 `--id` 参数（line 326）
- `list_tasks` 又单独添加了 `--task_id`（line 517）
- `main()` line 669-680 只传了 `args.task_id`，没传 `args.id`
- 用户用 `list_tasks --id 123` 时，参数被忽略
- **建议**: `list_tasks` 的 dispatch 里补上 `args.id` 的处理，或从 list_parser 移除 `--id`（用 `--task_id` 替代）
- **结果**: 已修复，`--id` 会映射到 `task_id`

### 5. `reset_task` 命令无 subparser，永远无法触发
- `main()` line 698-700 处理了 `reset_task` 命令
- 但 subparsers 中没有 `add_parser('reset_task', ...)`
- argparse 解析时不认识这个命令，代码不可达
- **建议**: 要么添加 subparser，要么删除 main 中的处理代码（已被 `reset_tasks` 替代）
- **结果**: 已修复，CLI dispatch 中已删除不可达分支

### 6. help 文本中英文混用
- 大部分 help 是中文（任务、筛选、状态 etc.）
- pool 相关命令用英文（Trigger workspace cleanup, Preview mode）
- **建议**: 统一为英文（与 CODEBASE.md 一致）
- **结果**: 已收敛为“面向 CLI/接口文档的中文说明 + 保留命令/字段字面量”的风格

## 缺少的测试

本轮已补充以下测试：

- `container/bisect/app/tests/test_bisect_api_client.py`
  - `list_tasks --id` 参数映射
  - `reset_failed --yes` dispatch
  - 非交互环境下确认逻辑
- `container/bisect/app/tests/test_query_builder.py`
  - `--commit` 短 SHA 前缀匹配
  - `--commit` 完整 SHA 精确匹配
  - `--git_url` REGEX 查询
  - `--error_id` 精确匹配

后续仍可继续补充：

- **参数解析测试**: 每个 subcommand 的 args 正确解析
- **条件构建测试**: `build_filter_conditions` 的映射（`--id` → `task_id`, `--commit` → `first_bad_commit`）
- **命令 dispatch 测试**: 每个 command 调用正确的 client 方法
- **互斥参数测试**: `new_task` 的 `--error_id` 和 `--metric` 互斥
