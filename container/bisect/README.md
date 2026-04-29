# Bisect Service User Guide

## 1. Overview

This document provides instructions for deploying, configuring, and using the Bisect Service.

The service is designed to automatically find the first bad commit that introduces a specific error (`error_id`) or performance regression (`bisect_metric`). It consists of the following main components:

-   **Web API**: A Flask-based API for submitting new bisect tasks and querying the system status.
-   **Producer**: A background worker that automatically discovers new potential bisect tasks from the `jobs` database.
-   **Consumer**: A background worker that picks up waiting tasks and performs the actual bisecting process.
-   **Verification Consumer**: An intelligent worker that verifies if a new task is similar to a previously successful one, allowing for result reuse and reducing redundant work.

## 2. Deployment and Running

The service is designed to run as a Docker container.

### Prerequisites

-   Docker installed and running.
-   Access to the Manticore Search database.

### Build the Docker Image

Navigate to the `compass-ci` root directory and use the provided build script:

```bash
bash container/bisect/build
```

This script will build the Docker image with the correct dependencies and configurations.

### Run the Docker Container

Use the provided start script to run the container. This script automatically sets the required environment variables and mounts necessary volumes.

```bash
ruby container/bisect/start
```

The service will start in the background. You can view the logs using:

```bash
docker logs -f bisect
```

**Note**: The `container/bisect/start` script contains various parameters (like database hosts, ports, etc.). You can modify this file directly to adjust the configuration for your environment.

### Development Mode (bind-mount local source)

Development mode runs the container with local source directories mounted into the container so code changes are visible immediately after restart.

Use one of the following methods:

```bash
# Method 1: one-shot environment variables for this command
BISECT_DEV_MODE=true \
HOST_CCI_SRC=/home/bisect/compass-ci \
HOST_LKP_SRC=/home/bisect/lkp-tests \
./start
```

```bash
# Method 2: export variables first
export BISECT_DEV_MODE=true
export HOST_CCI_SRC=/home/bisect/compass-ci
export HOST_LKP_SRC=/home/bisect/lkp-tests
./start
```

Important notes:

- `HOST_CCI_SRC` must point to the Compass-CI repo root that contains `container/bisect/app/__init__.py`.
- `HOST_LKP_SRC` must point to the lkp-tests repo root.
- In development mode, both mounts are read-write:
  - `HOST_CCI_SRC -> /c/compass-ci`
  - `HOST_LKP_SRC -> /c/lkp-tests`
- If variables are not exported (or not passed inline), `start` falls back to default paths and may mount an empty directory.

Quick verification:

```bash
docker inspect bisect --format '{{range .Mounts}}{{println .Destination " RW=" .RW " Source=" .Source}}{{end}}' | grep -E '/c/compass-ci|/c/lkp-tests'
docker exec -it bisect ls -la /c/compass-ci/container/bisect/app/__init__.py
docker exec -it bisect ls -la /c/compass-ci/container/bisect/services/commit_time_service/server.py
```

If you see `Error: Could not import 'app'`, check that `/c/compass-ci` inside the container is not empty and points to the correct host path.

## 3. Configuration

The service is configured via environment variables, which are set in the `container/bisect/start` script.

### Configuration Reload Semantics

Not every configuration change takes effect the same way. The current bisect service has three distinct behaviors:

| Change type | Examples | When it takes effect |
| :--- | :--- | :--- |
| Runtime mutable | `BISECT_PRODUCER_ENABLED`, `BISECT_METRICS_PRODUCER_ENABLED`, `BISECT_KERNEL_CI_PRODUCER_ENABLED`, `BISECT_ERROR_PRODUCER_ENABLED`, `PERFORMANCE_PRODUCER_ENABLED` via `/api/v1/toggle_producer`; `BISECT_CONSUMER_ENABLED` via `/api/v1/toggle_consumer` | Immediately, in memory only |
| Reload on next producer cycle | `container/bisect/config/errid_filters.yaml`, contents of the file pointed to by `CI_CONFIG_PATH` | Next producer cycle |
| Requires container recreate | Most environment variables in `container/bisect/lib/config.py`, `LOG_LEVEL`, `CCI_SRC`, `LKP_SRC`, `WORK_DIR`, Docker `-e/-v/-p`, `SUPERVISORD_CONF` | After recreating the container |

Important operational note:

- Editing `container/bisect/start` or changing Docker `-e` values does not take effect with `docker restart bisect`.
- In the current deployment model, those changes require recreating the container by running `ruby container/bisect/start` again.
- The detailed inventory and hot-reload candidates are tracked in `container/bisect/issues/config-reload-boundary.md`.
- `BISECT_PRODUCER_ENABLED=false` is the global master switch for all automatic producer components; a cycle already running is allowed to finish.
- `BISECT_METRICS_PRODUCER_ENABLED`, `BISECT_KERNEL_CI_PRODUCER_ENABLED`, `BISECT_ERROR_PRODUCER_ENABLED`, and `PERFORMANCE_PRODUCER_ENABLED` can be toggled independently via `/api/v1/toggle_producer?producer=<name>`.
- `BISECT_CONSUMER_ENABLED=false` pauses only new wait-task submissions and new verification submissions; in-flight work is not cancelled.

### Key Configuration Variables

| Variable | Description | Default Value |
| :--- | :--- | :--- |
| `MANTICORE_HOST` | The hostname or IP address of the Manticore Search database. | `manticore` |
| `MANTICORE_WRITE_PORT` | The HTTP port for the Manticore Search database. | `9308` |
| `BISECT_PRODUCER_ENABLED` | Global master switch for the automatic producer thread. Runtime toggles pause or resume future automatic cycles, but do not interrupt a cycle already running. | `true` |
| `BISECT_METRICS_PRODUCER_ENABLED` | Enable the daily metrics-collection producer component. Runtime toggle target: `metrics`. | `true` |
| `BISECT_KERNEL_CI_PRODUCER_ENABLED` | Enable the daily kernel-ci producer component. Runtime toggle target: `kernel_ci`. | `true` |
| `BISECT_ERROR_PRODUCER_ENABLED` | Enable the error-task producer component. Runtime toggle target: `error`. | `true` |
| `PERFORMANCE_PRODUCER_ENABLED` | Enable the performance-task producer component. Runtime toggle target: `performance`. | `true` |
| `BISECT_CONSUMER_ENABLED` | Enable new wait-task submission and new verification-job submission. Runtime toggles do not cancel in-flight thread-pool work. | `true` |
| `BISECT_CONSUMER_STARTUP_DELAY_SECONDS` | Startup grace period before new task consumption begins. The provided `container/bisect/start` script uses `300` so operators can pause consumption after restart if needed. | `0` (`300` via start script) |
| `BISECT_NOTIFICATION_WEBHOOK_URL` | Generic JSON webhook for HEAD validator notifications. Existing webhook payload semantics stay unchanged. | empty |
| `BISECT_FEISHU_WEBHOOK_URL` | Optional dedicated Feishu webhook for HEAD validator notifications. Sent in addition to the generic webhook when configured. | empty |
| `BISECT_FEISHU_SECRET` | Optional Feishu signing secret paired with `BISECT_FEISHU_WEBHOOK_URL`. | empty |
| `BISECT_THREADS` | The number of concurrent bisect tasks the consumer can run. | `8` |
| `SIMILARITY_THRESHOLD` | The score (0-100) above which two tasks are considered similar. | `70` |
| `LOG_LEVEL` | The logging level for the application. | `INFO` |

### Producer Component Roles

The producer family contains several independent components. The two names that are
easy to confuse are `metrics` and `performance`, but they serve different purposes:

| Component | Runtime target | What it does | Does it create bisect tasks? |
| :--- | :--- | :--- | :--- |
| Metrics Producer | `metrics` | Runs the daily metrics tracker script (`bisect_metrics_tracker.py --collect --plot`) to refresh statistics and plots. | No |
| Performance Producer | `performance` | Scans performance test results, identifies bisectable regressions, and creates `benchmark` bisect tasks. | Yes |
| Error Producer | `error` | Scans failed jobs and creates error bisect tasks from filtered errids. | Yes |
| Kernel CI Producer | `kernel_ci` | Runs the daily kernel-ci task generation flow. | Indirectly, via the kernel-ci producer script |

Status API fields are interpreted as follows:

- `configured_enabled`: the component's own switch value.
- `effective_enabled`: the component switch after the global `BISECT_PRODUCER_ENABLED`
  master switch is applied.
- Example: `configured_enabled=true` and `effective_enabled=false` means the component
  itself is enabled, but the global producer gate currently prevents it from running.

## 4. API Usage

The service exposes a simple REST API for interaction.

### 4.1. Create a New Bisect Task

-   **Endpoint**: `/new_bisect_task`
-   **Method**: `POST`
-   **Content-Type**: `application/json`

**Request Body (for an error bisect):**

```json
{
  "j": {
    "bad_job_id": "YOUR_BAD_JOB_ID",
    "error_id": "the.exact.error.id.string"
  }
}
```

**Request Body (for a performance bisect):**

```json
{
  "j": {
    "bad_job_id": "YOUR_BAD_JOB_ID",
    "bisect_metric": "the_performance_metric_name"
  }
}
```

**Example using `curl`:**

```bash
curl -X POST http://localhost:5000/new_bisect_task \
  -H "Content-Type: application/json" \
  -d 
  {
    "j": {
      "bad_job_id": "1234567890",
      "error_id": "makepkg.eid.fs/ioctl.c:warning:Excess-function-parameter"
    }
  }
```

### 4.2. List All Bisect Tasks

-   **Endpoint**: `/list_bisect_tasks`
-   **Method**: `GET`

Returns a JSON array of all tasks currently in the system.

### 4.3. Get Producer Status

-   **Endpoint**: `/producer_status`
-   **Method**: `GET`

Returns the current status of the automatic task producer (enabled or disabled).
The response also reports whether new automatic cycles are currently allowed and
whether the background producer thread is alive but paused, plus per-component
states for `metrics`, `kernel_ci`, `error`, and `performance`.

### 4.4. Toggle Consumer

-   **Endpoint**: `/toggle_consumer?state=enable|disable`
-   **Method**: `POST`

Runtime switch for new `BisectConsumer` submissions and new verification-job
submissions. Tasks already running in the thread pool continue to completion,
and submitted verification jobs still get polled for results.

### 4.5. Get Consumer Status

-   **Endpoint**: `/consumer_status`
-   **Method**: `GET`

Returns the current `BISECT_CONSUMER_ENABLED` state, whether new consumption is
currently allowed, the remaining startup-delay window, and liveness of the two
related worker threads.

## 5. Docker Service Details

### Container Architecture

The Bisect service runs as a single Docker container with multiple internal processes:

- **Flask API Server**: Port 9999 (internal), handles HTTP requests
- **BisectConsumer Thread**: Processes standard bisect tasks
- **VerificationConsumer Thread**: Handles intelligent task verification
- **Producer Thread**: Discovers new tasks (if enabled)
- **Repository Cleanup Thread**: Maintains disk space

### Volume Mounts

The container requires several volume mounts for proper operation:

```bash
# Git repository cache
-v /srv/git:/srv/git:rw

# Result storage
-v /srv/result:/srv/result:rw

# Log output
-v /srv/log:/srv/log:rw
```

### Network Requirements

- Access to Manticore Search database (default port 9308)
- Access to internal job submission system
- Git repository access for cloning and fetching

### Resource Recommendations

- **CPU**: Minimum 4 cores, recommended 8+ cores for parallel bisecting
- **Memory**: Minimum 8GB, recommended 16GB+
- **Disk**: At least 100GB for repository caching
- **Network**: Stable connection for Git operations

## 6. Monitoring and Health Checks

### Log Files

Logs are organized by component in `/result/bisect/logs/`:

```
logs/
├── consumer/       # Consumer, validator, task_processor
│   ├── consumer.log
│   └── error.log
├── producer/       # Producer cycles and reports
│   ├── producer.log
│   └── error.log
├── api/            # Flask REST API
│   ├── api.log
│   └── error.log
├── commit-service/ # Commit time service
│   ├── service.log
│   └── error.log
└── performance/    # Performance metrics
    └── performance.log
```

Daily rotation appends `.YYYY-MM-DD` suffix. Old logs auto-cleaned after 30 days.

### Health Check Endpoint

- **Endpoint**: `/health`
- **Method**: `GET`
- **Healthy Response**: `200 OK` with system status JSON

### Monitoring Metrics

Key metrics to monitor:

1. **Task Queue Depth**: Number of tasks in `wait` status
2. **Processing Rate**: Tasks completed per hour
3. **Success Rate**: Percentage of successful bisects
4. **Verification Hit Rate**: Percentage of tasks resolved by verification
5. **Repository Cache Size**: Disk usage in `/srv/git`

### Repository cache layout

To reduce hotspot contention, bisect workers and commit-time queries use separate pristine roots:

- Bisect worker pristine (for `--reference` clones): `${WORK_DIR}/bisect_repos/pristine`
- Commit query pristine (for parent/ancestor/tag lookup): `${WORK_DIR}/bisect_repos/pristine_query`

In the default container setup (`WORK_DIR=/c/bisect`), these map to:

- `/c/bisect/bisect_repos/pristine`
- `/c/bisect/bisect_repos/pristine_query`

## 7. Troubleshooting

### Common Issues and Solutions

#### Container Won't Start

**Symptom**: Container exits immediately after starting

**Solution**:
```bash
# Check container logs
docker logs bisect

# Verify environment variables
docker exec bisect env | grep BISECT

# Check database connectivity
docker exec bisect python -c "from manticore_simple import ManticoreClient; print('DB OK')"
```

#### Tasks Stuck in 'processing' State

**Symptom**: Tasks remain in processing state for hours

**Solution**:
```bash
# Reset stuck tasks (container will automatically reset on restart)
docker restart bisect

# Check for Git repository issues
docker exec bisect ls -la /srv/git/
```

#### High Memory Usage

**Symptom**: Container consuming excessive memory

**Solution**:
```bash
# Reduce concurrent threads
# Edit container/bisect/start and set:
export BISECT_THREADS=4

# Recreate the container so new env values are applied
ruby container/bisect/start
```

#### Disk Space Issues

**Symptom**: "No space left on device" errors

**Solution**:
```bash
# Clean up old repositories
docker exec bisect rm -rf /srv/git/bisect_repos/workspaces/*

# Remove old log files
find /srv/log/bisect -name "*.log" -mtime +30 -delete
```

## 8. Advanced Configuration

### Custom Error Filtering

To customize which errors trigger bisect tasks, modify the error intelligence configuration:

```bash
# Edit the whitelist in the database
# Use Manticore SQL to update the regression table
```

### Performance Tuning

For high-load environments, consider these optimizations:

1. **Increase Thread Pool**:
   ```bash
   export BISECT_THREADS=16  # For systems with many cores
   ```

2. **Enable Repository Caching**:
   ```bash
   export GIT_CACHE_ENABLED=true
   export GIT_CACHE_SIZE_GB=200
   ```

3. **Adjust Similarity Threshold**:
   ```bash
   export SIMILARITY_THRESHOLD=85  # More strict matching
   ```

### Integration with CI/CD

The service can be integrated with your CI/CD pipeline:

1. **Webhook Integration**: Configure your CI system to POST to `/new_bisect_task`
2. **Polling Integration**: Use the `/list_bisect_tasks` endpoint to check task status
3. **Event-Driven**: Future support for message queue integration (see DESIGN.md)

## 9. Maintenance

### Regular Maintenance Tasks

1. **Weekly**: Clean up completed tasks older than 30 days
2. **Monthly**: Optimize Manticore indexes
3. **Quarterly**: Review and update error whitelists

### Backup and Recovery

Important data to backup:

- Manticore database (bisect and regression tables)
- Configuration files in `/compass-ci/container/bisect/`
- Log files for audit purposes

### Upgrading

To upgrade the service:

1. Build new image: `bash container/bisect/build`
2. Stop current container: `docker stop bisect`
3. Start new container: `ruby container/bisect/start`

## 10. Further Reading

| Document | Description |
|----------|-------------|
| [docs/INDEX.md](docs/INDEX.md) | Document index — links to all docs, configs, issues |
| [docs/CODEBASE.md](docs/CODEBASE.md) | Code map — every file's path and purpose |
| [docs/DESIGN.md](docs/DESIGN.md) | Architecture deep dive |
| [docs/TESTING.md](docs/TESTING.md) | Unit tests and post-deploy validation |
| [docs/API_DOCUMENTATION.md](docs/API_DOCUMENTATION.md) | REST API reference |
| [docs/DATA_BASE.md](docs/DATA_BASE.md) | ManticoreSearch schema |
