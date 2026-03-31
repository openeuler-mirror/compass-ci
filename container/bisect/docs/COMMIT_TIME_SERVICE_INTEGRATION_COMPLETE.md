# Commit Time Service 集成完成总结

## 已完成的工作

### 1. 服务实现
- ✅ `commit_query.py` - 核心 commit 时间查询逻辑 (复用 SharedRepoManager)
- ✅ `cache.py` - LRU 缓存层
- ✅ `server.py` - HTTP REST API 服务
- ✅ `client.py` - 客户端库
- ✅ 完整的测试套件

### 2. 容器部署配置
- ✅ 修改 `Dockerfile` 添加 supervisor 包
- ✅ 创建 `config/supervisord.conf` 配置两个服务
- ✅ 修改 `start` 文件使用 supervisord 启动
- ✅ 添加环境变量配置:
  - `COMMIT_TIME_SERVICE_URL=http://localhost:8765`
  - `BISECT_MAX_COMMIT_AGE_DAYS=365`
- ✅ 暴露端口 8765

### 3. Producer 集成
- ✅ 在 `bisect_utils.py` 中添加 `extract_commit_from_full_text_kv()` 函数
- ✅ 在 `bisect_producer.py` 中集成 CommitTimeClient
- ✅ 在生产者循环中添加 commit 年龄过滤逻辑
- ✅ 添加统计和日志输出

## 集成细节

### bisect_producer.py 的改动

1. **导入 CommitTimeClient** (第 40-46 行)
```python
try:
    from client import CommitTimeClient
    COMMIT_TIME_CLIENT_AVAILABLE = True
except ImportError:
    logger.warning("Commit Time Service Client not available, commit age filtering disabled")
    COMMIT_TIME_CLIENT_AVAILABLE = False
```

2. **初始化客户端** (第 73-87 行)
```python
if COMMIT_TIME_CLIENT_AVAILABLE:
    commit_service_url = config.get(
        'commit_time_service_url',
        os.environ.get('COMMIT_TIME_SERVICE_URL', 'http://localhost:8765')
    )
    self.commit_client = CommitTimeClient(commit_service_url)
    self.max_commit_age_days = config.get(
        'max_commit_age_days',
        int(os.environ.get('BISECT_MAX_COMMIT_AGE_DAYS', '365'))
    )
    logger.info(f"Commit 年龄过滤已启用 | 服务: {commit_service_url} | 最大年龄: {self.max_commit_age_days} 天")
else:
    self.commit_client = None
```

3. **过滤逻辑** (第 258-281 行)
```python
# 6. Commit 年龄过滤（有 commit time client 时执行）
if self.commit_client:
    commit_age_start = time.time()
    commit_hash = extract_commit_from_full_text_kv(full_text_kv)

    if commit_hash:
        try:
            is_too_old = self.commit_client.is_commit_too_old(
                git_url,
                commit_hash,
                self.max_commit_age_days
            )

            if is_too_old:
                stats.setdefault('tasks_filtered_old_commits', 0)
                stats['tasks_filtered_old_commits'] += 1
                logger.info(f"过滤旧 commit | job_id: {bad_job_id} | commit: {commit_hash[:12]}... | 超过 {self.max_commit_age_days} 天")
                continue

        except Exception as e:
            logger.warning(f"Commit 年龄检查失败 | job_id: {bad_job_id} | 错误: {str(e)} | 继续处理")

    stats.setdefault('commit_age_check_time_ms', 0)
    stats['commit_age_check_time_ms'] += (time.time() - commit_age_start) * 1000
```

4. **统计输出** (第 145, 467-473 行)
```python
# 统计初始化
'tasks_filtered_old_commits': 0,  # 新增：被 commit 年龄过滤的任务数

# 日志输出
if stats.get('avg_commit_age_check_ms', 0) > 0:
    logger.info(f"  Commit年龄检查: {stats.get('avg_commit_age_check_ms', 0):.2f}ms")

if stats.get('tasks_filtered_old_commits', 0) > 0:
    logger.info(f"Commit 年龄过滤统计 | 过滤数: {stats['tasks_filtered_old_commits']} | "
               f"阈值: {self.max_commit_age_days} 天")
```

## 部署步骤

### 1. 重新构建镜像

```bash
cd /home/shiptux/git/gitee/compass-ci
./build bisect
```

### 2. 启动容器

```bash
cd /home/shiptux/git/gitee/compass-ci/container/bisect
./start
```

### 3. 验证服务

```bash
# 进入容器
docker exec -it bisect sh

# 检查进程
ps aux | grep python
# 应该看到:
# - python3 .../commit_time_service/server.py
# - flask run

# 检查 supervisord 状态
supervisorctl status
# 应该显示:
# commit-time-service    RUNNING
# flask-api              RUNNING

# 检查 commit time service
curl http://localhost:8765/health
# 应返回: {"status": "healthy", ...}

# 检查 Flask API
curl http://localhost:9999/
# 应返回 API 响应

# 查看日志
tail -f /tmp/commit-time-service.log
tail -f /tmp/flask.log
```

### 4. 从宿主机测试

```bash
# 测试 commit time service
curl "http://localhost:8765/api/v1/commit/time?repo=https://gitee.com/openeuler/kernel.git&commit=5e5d40e65cb5"

# 查看统计
curl http://localhost:8765/api/v1/stats
```

### 5. 查看 producer 日志

```bash
# 容器内查看 producer 日志
docker exec -it bisect sh
tail -f /tmp/flask.log | grep "Commit"

# 应该看到类似:
# Commit 年龄过滤已启用 | 服务: http://localhost:8765 | 最大年龄: 365 天
# 过滤旧 commit | job_id: xxx | commit: abc123... | 超过 365 天
```

## 配置选项

### 环境变量

在 `start` 文件中已配置:

- `COMMIT_TIME_SERVICE_URL=http://localhost:8765` - 服务地址
- `BISECT_MAX_COMMIT_AGE_DAYS=365` - 最大年龄阈值(天)

可以通过修改 `start` 文件调整这些值。

### Supervisord 配置

位置: `config/supervisord.conf`

可以修改:
- 缓存大小: `--cache-size 10000`
- 日志位置: `/tmp/commit-time-service.log`
- 自动重启: `autorestart=true`

## 降级策略

如果 commit time service 不可用:
- Producer 会继续正常运行
- 不会过滤任何任务 (降级策略)
- 会输出警告日志

这保证了系统的鲁棒性。

## 性能影响

根据设计:

1. **缓存命中率**: 预计 70-90%
2. **平均查询耗时**:
   - 缓存命中: ~1ms
   - 缓存未命中: ~50-100ms (取决于 git 操作)
3. **Producer 影响**: 每个 job 增加 1-100ms 处理时间

## 监控指标

Producer 会输出以下统计:

- `tasks_filtered_old_commits` - 被过滤的旧 commit 任务数
- `commit_age_check_time_ms` - commit 年龄检查总耗时
- `avg_commit_age_check_ms` - 平均检查耗时

Commit Time Service 提供:
- `/api/v1/stats` - 缓存命中率、查询次数等

## 故障排查

### 问题 1: 服务无法启动

```bash
# 检查 supervisord 日志
docker exec -it bisect cat /tmp/supervisord.log

# 检查服务错误日志
docker exec -it bisect cat /tmp/commit-time-service-error.log
```

### 问题 2: Producer 未启用过滤

检查日志是否有:
```
Commit 年龄过滤已启用 | 服务: http://localhost:8765 | 最大年龄: 365 天
```

如果没有,可能是:
- Client 导入失败
- 服务 URL 配置错误

### 问题 3: 过滤不生效

1. 确认服务正常: `curl http://localhost:8765/health`
2. 测试 commit 提取: 检查 full_text_kv 格式
3. 查看日志: 是否有 "过滤旧 commit" 消息

## 下一步

- ✅ 代码集成完成
- ⏳ 待测试: 部署并验证功能
- ⏳ 待观察: 生产环境性能表现
- ⏳ 待优化: 根据实际使用调整缓存大小和阈值

## 文件清单

### 新增文件
- `services/commit_time_service/commit_query.py`
- `services/commit_time_service/cache.py`
- `services/commit_time_service/server.py`
- `services/commit_time_service/client.py`
- `services/commit_time_service/tests/` (测试文件)
- `docs/COMMIT_TIME_SERVICE.md`
- `docs/COMMIT_TIME_SERVICE_IMPLEMENTATION_SUMMARY.md`
- `docs/COMMIT_TIME_SERVICE_CONTAINER_DEPLOYMENT.md`
- `config/supervisord.conf`

### 修改文件
- `Dockerfile` - 添加 supervisor
- `start` - 使用 supervisord 启动
- `lib/bisect_utils.py` - 添加 extract_commit_from_full_text_kv()
- `core/bisect_producer.py` - 集成 commit 过滤逻辑

## 总结

✅ Commit time service 已完全集成到 bisect producer
✅ 使用 supervisord 在同一容器运行两个服务
✅ 复用 SharedRepoManager 的 pristine 仓库
✅ 实现了降级策略,保证系统鲁棒性
✅ 添加了完整的统计和监控

准备部署测试!
