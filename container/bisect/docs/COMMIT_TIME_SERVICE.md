# Commit Time Service

Git commit 时间查询服务，为 bisect 和其他系统提供 commit 年龄检查。

## 特性

- 复用 `SharedRepoManager` 的 pristine 仓库，无需额外存储
- LRU 缓存机制，减少重复查询
- REST API 接口
- 支持 commit 年龄检查
- 线程安全

## 架构

```
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐
│ HTTP Client  │ --> │ Commit Time       │ --> │ SharedRepo      │
│ (Producer)   │     │ Service           │     │ Manager         │
└──────────────┘     │ - Query Layer     │     │ - Pristine Pool │
                     │ - Cache Layer     │     └─────────────────┘
                     └───────────────────┘            │
                                                      ↓
                                                ┌─────────────────┐
                                                │ Internal Mirror │
                                                │ Git Repos       │
                                                └─────────────────┘
```

## API

### 1. 获取 commit 时间信息

```
GET /api/v1/commit/time?repo=<git_url>&commit=<hash>
```

**参数:**
- `repo`: Git 仓库 URL
- `commit`: Commit hash（完整或简短）

**响应:**
```json
{
  "status": "success",
  "cached": false,
  "data": {
    "commit": "5e5d40e65cb55e4699c9879674a004f246606a8d",
    "timestamp": 1731394000,
    "date": "2024-11-12T05:53:20Z",
    "age_days": 6,
    "author": "Zhang San",
    "subject": "fix: some bug"
  }
}
```

### 2. 检查 commit 是否过旧

```
GET /api/v1/commit/check?repo=<git_url>&commit=<hash>&max_age_days=365
```

**参数:**
- `repo`: Git 仓库 URL
- `commit`: Commit hash
- `max_age_days`: 最大天数阈值（可选，默认 365）

**响应:**
```json
{
  "status": "success",
  "cached": false,
  "data": {
    "commit": "5e5d40e65cb55e4699c9879674a004f246606a8d",
    "age_days": 6,
    "max_age_days": 365,
    "is_too_old": false
  }
}
```

### 3. 获取服务统计

```
GET /api/v1/stats
```

**响应:**
```json
{
  "uptime_seconds": 3600,
  "total_requests": 1000,
  "cache_hits": 800,
  "cache_hit_rate": 0.8,
  "cache_stats": {
    "timestamp_cache_size": 500,
    "info_cache_size": 450,
    "max_size": 10000,
    "ttl": 86400,
    "hit_rate": 0.8,
    "evictions": 0
  }
}
```

### 4. 健康检查

```
GET /health
```

**响应:**
```json
{
  "status": "healthy"
}
```

## 安装

### 依赖

服务依赖 `container/bisect/lib` 中的组件：
- `SharedRepoManager` - 仓库管理
- `LRUCache` - 缓存
- `log_config` - 日志系统

无需额外 Python 依赖。

### 环境变量

```bash
export CCI_SRC=/srv/cci
export WORK_DIR=/tmp
export LKP_SRC=/srv/lkp
```

## 使用

### 启动服务

```bash
cd /srv/cci/container/bisect/services/commit_time_service
python3 server.py
```

**参数:**
```bash
python3 server.py \
  --host 0.0.0.0 \
  --port 8765 \
  --cache-size 10000 \
  --cache-ttl 86400
```

### 测试查询

```bash
# 测试 commit 时间查询
curl "http://localhost:8765/api/v1/commit/time?repo=https://gitee.com/openeuler/kernel.git&commit=5e5d40e65cb5"

# 测试年龄检查
curl "http://localhost:8765/api/v1/commit/check?repo=https://gitee.com/openeuler/kernel.git&commit=5e5d40e65cb5&max_age_days=365"

# 查看统计
curl "http://localhost:8765/api/v1/stats"

# 健康检查
curl "http://localhost:8765/health"
```

## 在 bisect_producer 中集成

### 1. 添加配置

在 `container/bisect/lib/config.py` 中添加：

```python
# Commit Time Service
COMMIT_TIME_SERVICE_URL = os.environ.get('COMMIT_TIME_SERVICE_URL', 'http://localhost:8765')
COMMIT_MAX_AGE_DAYS = int(os.environ.get('COMMIT_MAX_AGE_DAYS', '365'))
```

### 2. 在 Producer 中使用

```python
import requests

class ErrorBisectProducer:
    def __init__(self, client, config):
        self.commit_service_url = config.get(
            'commit_time_service_url',
            'http://localhost:8765'
        )
        self.max_commit_age_days = config.get('max_commit_age_days', 365)

    def _check_commit_age(self, git_url: str, commit_hash: str) -> bool:
        """
        检查 commit 是否过旧

        Returns:
            True: commit 可以使用（未超过阈值）
            False: commit 太旧，应该过滤
        """
        try:
            response = requests.get(
                f"{self.commit_service_url}/api/v1/commit/check",
                params={
                    'repo': git_url,
                    'commit': commit_hash,
                    'max_age_days': self.max_commit_age_days
                },
                timeout=10
            )

            if response.status_code == 200:
                result = response.json()
                if result['status'] == 'success':
                    is_too_old = result['data']['is_too_old']
                    age_days = result['data']['age_days']

                    if is_too_old:
                        logger.info(f"Commit too old | commit: {commit_hash[:12]} | age: {age_days} days")
                        return False
                    return True

            # 如果查询失败，不过滤（降级策略）
            logger.warning(f"Commit age check failed | commit: {commit_hash[:12]}")
            return True

        except Exception as e:
            logger.error(f"Commit age check error: {str(e)}")
            return True  # 降级策略：查询失败不过滤
```

### 3. 在任务创建前过滤

```python
# 在 execute_producer_cycle 中
for item in result:
    # ... 现有逻辑 ...

    # 提取 commit（从 full_text_kv）
    commit_hash = self._extract_commit_from_kv(full_text_kv)

    if commit_hash:
        # 检查 commit 年龄
        if not self._check_commit_age(git_url, commit_hash):
            stats.setdefault('filtered_old_commits', 0)
            stats['filtered_old_commits'] += 1
            continue  # 跳过这个任务

    # ... 继续创建任务 ...
```

## 测试

### 单元测试

```bash
cd /srv/cci/container/bisect/services/commit_time_service/tests
python3 -m pytest test_commit_query.py
python3 -m pytest test_cache.py
```

### 集成测试

```bash
python3 -m pytest test_service_integration.py
```

### 手动测试组件

```bash
# 测试 commit_query
python3 commit_query.py

# 测试 cache
python3 cache.py
```

## 性能

### 缓存效果

- **首次查询**: ~100-500ms (git log 命令)
- **缓存命中**: <1ms (内存读取)
- **预期命中率**: 70-90% (相同 commit 反复查询)

### 资源占用

- **内存**: ~100MB (10000 条缓存)
- **磁盘**: 使用 SharedRepoManager 的 pristine 仓库，无额外开销

### 并发能力

- 受 SharedRepoManager 的 pristine 锁保护
- 同一仓库串行查询，不同仓库并行
- 建议配合缓存使用以提高并发性能

## 部署

### systemd 服务

见 `systemd/commit-time-service.service`

```bash
sudo cp systemd/commit-time-service.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start commit-time-service
sudo systemctl enable commit-time-service
```

### 监控

- 日志: 使用项目统一的 log_config
- 统计: `/api/v1/stats` 端点
- 健康检查: `/health` 端点

## 故障排查

### 服务无法启动

检查环境变量：
```bash
echo $CCI_SRC
echo $WORK_DIR
echo $LKP_SRC
```

### Commit 查询失败

1. 检查 pristine 仓库是否存在
2. 检查网络连接（初次克隆需要访问镜像源）
3. 检查 commit hash 是否正确

### 缓存未生效

1. 检查 TTL 配置
2. 查看 `/api/v1/stats` 确认缓存状态

## 维护

### 清理旧仓库

SharedRepoManager 会自动管理 pristine 仓库，无需手动清理。

### 调整缓存大小

根据实际使用情况调整 `--cache-size` 参数。

## 许可

Same as Compass-CI project
