# Commit Time Service 容器部署指南

## 当前容器架构

当前 bisect 容器运行：
- Flask API 服务（端口 9999）
- 环境：Alpine Linux
- 用户：bisect (uid=30116)
- 工作目录：`/c/bisect`

## 集成方案

有两种部署方式：

### 方案 1：同容器部署（推荐）

将 commit time service 作为后台进程运行在同一个 bisect 容器中。

#### 优点
- 共享 SharedRepoManager 和 pristine 仓库
- 无需额外容器
- 网络通信最快（localhost）
- 部署简单

#### 实施步骤

**1. 修改 `start` 文件**

在启动 Flask 之前启动 commit time service。

```ruby
#!/usr/bin/env ruby
# ... 现有代码 ...

# 修改启动命令，使用 supervisor 或多进程启动
cmd += ['sh', '-c', 'umask 002 && \
  python3 $CCI_SRC/container/bisect/services/commit_time_service/server.py \
    --host 0.0.0.0 --port 8765 --cache-size 10000 > /tmp/commit-time-service.log 2>&1 & \
  flask run --host=0.0.0.0 --port=9999']
```

**2. 添加环境变量**

在 `start` 文件中添加 commit time service 配置：

```ruby
cmd = %w[
  docker run
  --name bisect
  --restart=always
  -itd
] + env + %W[
  -e LKP_SRC=#{DEFAULT_LKP}
  -e CCI_SRC=#{DEFAULT_CCI}
  -e MANTICORE_HOST=#{MANTICORE_HOST}
  -e BISECT_PRODUCER_ENABLED=true
  -e FLASK_APP=#{FLASK_APP}
  -e LOG_LEVEL=DEBUG
  -e USE_HTTP_CLIENT=true
  -e BISECT_THREADS=32
  -e COMMIT_TIME_SERVICE_URL=http://localhost:8765
  -e BISECT_MAX_COMMIT_AGE_DAYS=365
  -e WORK_DIR=#{BISECT_WORK_DIR}
  -v #{HOST_WORK_DIR}:#{BISECT_WORK_DIR}
  # ... 其他挂载 ...
]
```

**3. 使用 supervisord（更优雅的方式）**

修改 Dockerfile 添加 supervisord：

```dockerfile
# 在 Dockerfile 中添加
RUN apk add --no-cache supervisor

# 添加 supervisor 配置目录
RUN mkdir -p /etc/supervisor/conf.d
```

创建 `container/bisect/supervisord.conf`：

```ini
[supervisord]
nodaemon=true
user=bisect
logfile=/tmp/supervisord.log
pidfile=/tmp/supervisord.pid

[program:commit-time-service]
command=python3 /c/compass-ci/container/bisect/services/commit_time_service/server.py --host 0.0.0.0 --port 8765
directory=/c/bisect
user=bisect
autostart=true
autorestart=true
stdout_logfile=/tmp/commit-time-service.log
stderr_logfile=/tmp/commit-time-service-error.log
environment=CCI_SRC="/c/compass-ci",WORK_DIR="/c/bisect",LKP_SRC="/c/lkp-tests"

[program:flask-api]
command=flask run --host=0.0.0.0 --port=9999
directory=/c/bisect
user=bisect
autostart=true
autorestart=true
stdout_logfile=/tmp/flask.log
stderr_logfile=/tmp/flask-error.log
environment=FLASK_APP="/c/compass-ci/container/bisect/app/__init__.py",CCI_SRC="/c/compass-ci",WORK_DIR="/c/bisect",LKP_SRC="/c/lkp-tests"
```

修改 `start` 文件使用 supervisord：

```ruby
# 复制 supervisord 配置
cmd = %w[
  docker run
  --name bisect
  --restart=always
  -itd
] + env + %W[
  # ... 现有环境变量 ...
  -v /path/to/supervisord.conf:/etc/supervisor/supervisord.conf:ro
  -p 9999:9999
  -p 8765:8765
  bisect
]

cmd += ['supervisord', '-c', '/etc/supervisor/supervisord.conf']
```

### 方案 2：独立容器部署

将 commit time service 作为独立容器运行。

#### 优点
- 服务独立，故障隔离
- 可以独立扩展
- 其他系统也可以使用

#### 缺点
- 需要共享 pristine 仓库目录
- 网络通信开销
- 部署复杂度增加

#### 实施步骤

**1. 创建 `container/commit-time-service/Dockerfile`**

```dockerfile
FROM alpine

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
    && apk update

RUN apk add --no-cache git python3 py3-requests

RUN addgroup -g 30118 -S commit-service && adduser -u 30117 -S commit-service -G commit-service

ENV CCI_SRC /c/compass-ci
ENV WORK_DIR /c/bisect
ENV LKP_SRC /c/lkp-tests

WORKDIR /c/commit-service

USER commit-service

COPY --chown=commit-service:commit-service compass-ci/container/bisect/services/commit_time_service /c/commit-service
COPY --chown=commit-service:commit-service compass-ci/container/bisect/lib /c/compass-ci/container/bisect/lib

EXPOSE 8765

CMD ["python3", "server.py", "--host", "0.0.0.0", "--port", "8765"]
```

**2. 创建 `container/commit-time-service/start`**

```ruby
#!/usr/bin/env ruby

docker_rm 'commit-time-service'

BISECT_WORK_DIR = '/c/bisect'
HOST_WORK_DIR = '/tmp/'

cmd = %w[
  docker run
  --name commit-time-service
  --restart=always
  -d
  -e CCI_SRC=/c/compass-ci
  -e WORK_DIR=/c/bisect
  -e LKP_SRC=/c/lkp-tests
  -v /tmp:/c/bisect
  -p 8765:8765
  commit-time-service
]

system(*cmd)
```

**3. 修改 bisect 的 `start` 文件**

```ruby
# 添加环境变量指向独立服务
cmd = %w[
  docker run
  --name bisect
  # ...
] + env + %W[
  # ...
  -e COMMIT_TIME_SERVICE_URL=http://172.17.0.1:8765
  # 或使用 --link
  --link commit-time-service:commit-time-service
  -e COMMIT_TIME_SERVICE_URL=http://commit-time-service:8765
  # ...
]
```

## 推荐部署方案（方案 1 + supervisord）

这是最优雅和高效的方案。

### 完整实施步骤

#### 1. 修改 Dockerfile

```dockerfile
# 在原有 Dockerfile 基础上添加
RUN apk add --no-cache supervisor

# 创建 supervisor 配置目录
RUN mkdir -p /etc/supervisor/conf.d /var/log/supervisor
```

#### 2. 创建 supervisord 配置文件

创建 `container/bisect/config/supervisord.conf`：

```ini
[supervisord]
nodaemon=true
user=bisect
logfile=/var/log/supervisor/supervisord.log
pidfile=/tmp/supervisord.pid
loglevel=info

[program:commit-time-service]
command=python3 %(ENV_CCI_SRC)s/container/bisect/services/commit_time_service/server.py --host 0.0.0.0 --port 8765 --cache-size 10000
directory=%(ENV_WORK_DIR)s
user=bisect
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/commit-time-service.log
stderr_logfile=/var/log/supervisor/commit-time-service-error.log
environment=CCI_SRC="%(ENV_CCI_SRC)s",WORK_DIR="%(ENV_WORK_DIR)s",LKP_SRC="%(ENV_LKP_SRC)s"

[program:flask-api]
command=flask run --host=0.0.0.0 --port=9999
directory=%(ENV_WORK_DIR)s
user=bisect
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/flask.log
stderr_logfile=/var/log/supervisor/flask-error.log
environment=FLASK_APP="%(ENV_FLASK_APP)s",CCI_SRC="%(ENV_CCI_SRC)s",WORK_DIR="%(ENV_WORK_DIR)s",LKP_SRC="%(ENV_LKP_SRC)s"
```

#### 3. 修改 start 文件

```ruby
#!/usr/bin/env ruby
# ... 现有代码保持不变 ...

SUPERVISORD_CONF = File.join(__dir__, 'config/supervisord.conf')

cmd = %w[
  docker run
  --name bisect
  --restart=always
  -itd
] + env + %W[
  -e LKP_SRC=#{DEFAULT_LKP}
  -e CCI_SRC=#{DEFAULT_CCI}
  -e MANTICORE_HOST=#{MANTICORE_HOST}
  -e BISECT_PRODUCER_ENABLED=true
  -e FLASK_APP=#{FLASK_APP}
  -e LOG_LEVEL=DEBUG
  -e USE_HTTP_CLIENT=true
  -e BISECT_THREADS=32
  -e COMMIT_TIME_SERVICE_URL=http://localhost:8765
  -e BISECT_MAX_COMMIT_AGE_DAYS=365
  -e WORK_DIR=#{BISECT_WORK_DIR}
  -v #{HOST_WORK_DIR}:#{BISECT_WORK_DIR}
  -v #{HOST_RESULT_DIR}:#{BISECT_RESULT_DIR}
  -v #{HOST_RESULT_DIR}:#{HOST_RESULT_DIR}
  -v #{DEFAULT_CACHE}:#{DEFAULT_CACHE}
  -v #{DEFAULT_CONFIG_DIR}:#{DEFAULT_CONFIG_DIR}:ro
  -v #{DEFAULT_USER_CONFIG_DIR}:#{DEFAULT_BISECT_CONFIG_DIR}:ro
  -v #{SUPERVISORD_CONF}:/etc/supervisor/supervisord.conf:ro
  -v /etc/localtime:/etc/localtime:ro
  -v /etc/compass-ci/register:/etc/compass-ci/register:ro
  -p 9999:9999
  -p 8765:8765
  bisect
]

# 使用 supervisord 启动
cmd += ['supervisord', '-c', '/etc/supervisor/supervisord.conf']

system(*cmd)
```

## 部署验证

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

# 检查 commit time service
curl http://localhost:8765/health

# 检查 Flask API
curl http://localhost:9999/

# 查看日志
tail -f /var/log/supervisor/commit-time-service.log
tail -f /var/log/supervisor/flask.log
```

### 4. 从宿主机测试

```bash
# 测试 commit time service
curl "http://localhost:8765/api/v1/commit/time?repo=https://gitee.com/openeuler/kernel.git&commit=5e5d40e65cb5"

# 查看统计
curl http://localhost:8765/api/v1/stats
```

## 监控和维护

### 日志位置

- Commit Time Service: `/var/log/supervisor/commit-time-service.log`
- Flask API: `/var/log/supervisor/flask.log`
- Supervisord: `/var/log/supervisor/supervisord.log`

### 重启服务

```bash
# 进入容器
docker exec -it bisect sh

# 重启 commit time service
supervisorctl restart commit-time-service

# 重启 flask
supervisorctl restart flask-api

# 查看状态
supervisorctl status
```

## 总结

**推荐方案**: 使用 supervisord 在同一容器中运行两个服务

**优点**:
- ✅ 共享资源（pristine 仓库）
- ✅ 无网络开销
- ✅ 统一部署和管理
- ✅ 进程监控和自动重启

**需要修改的文件**:
1. `container/bisect/Dockerfile` - 添加 supervisor
2. `container/bisect/config/supervisord.conf` - 新建配置文件
3. `container/bisect/start` - 修改启动命令

这样部署后，bisect producer 就可以通过 `http://localhost:8765` 访问 commit time service 进行年龄过滤了。
