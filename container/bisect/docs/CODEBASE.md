# Bisect Service Codebase Map

Automated bisect service for kernel build errors and performance regressions.
Runs as a Docker container with supervisord managing multiple processes.

## Architecture

```
                    ┌─────────────┐
                    │  Flask API  │  ← External task submission
                    │  (port 9999)│
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌─────────────┐ ┌─────────────┐ ┌──────────────┐
    │  Producer   │ │  Consumer   │ │  Validator    │
    │ (periodic)  │ │ (polling)   │ │ (polling)     │
    └──────┬──────┘ └──────┬──────┘ └──────┬───────┘
           │               │               │
           ▼               ▼               ▼
    ┌──────────────────────────────────────────────┐
    │         ManticoreSearch (bisect index)        │
    └──────────────────────────────────────────────┘
```

## Data flow

```
jobs table (ManticoreSearch)
  → Producer: query error jobs → extract error_ids → filter → dedup → INSERT bisect tasks
  → Consumer: pick wait tasks → clone repo → git bisect run → mark success/failed
  → Validator: verify success results → mark similar tasks → write regression records
```

## Core (`core/`)

```
core/task_processor.py
  path: container/bisect/core/task_processor.py
  description: Main orchestrator. Initializes thread pool, repo manager, and
    launches Producer/Consumer/Validator as background threads. Manages task
    locks, backpressure (semaphore), and graceful shutdown.

core/bisect_producer.py
  path: container/bisect/core/bisect_producer.py
  description: Auto-discovers bisect tasks from the jobs table.
    ErrorBisectProducer: queries failed jobs, extracts error_ids, filters noise
    via errid_intelligence, batch dedup against bisect index, creates tasks.
    PerformanceBisectProducer: queries performance test jobs, detects regressions
    by comparing metrics across commit pairs, validates ancestry.
    Pipeline: Phase 0 (collect) → Phase 1 (commit age) → Phase 2 (errid filter)
    → Phase 3 (dedup) → Phase 3b (reset failed) → Phase 4 (batch create).

core/bisect_consumer.py
  path: container/bisect/core/bisect_consumer.py
  description: Processes individual bisect tasks. Clones repo via repo_manager,
    runs git bisect with the bisect script, parses results, updates task status.
    Handles retry logic and j-field merge for failed/wait transitions.

core/verification_consumer.py
  path: container/bisect/core/verification_consumer.py
  description: Post-bisect verification. When a bisect finds first_bad_commit,
    this consumer verifies the result is reproducible. On success, writes
    regression records. On failure, resets task to wait for retry.

core/polling_worker.py
  path: container/bisect/core/polling_worker.py
  description: Base class for database-polling background threads. Provides
    exponential backoff, condition-variable-based wake (no 5s polling), and
    stop signal handling. Used by Consumer and Validator workers.
```

## Libraries (`lib/`)

```
lib/config.py
  path: container/bisect/lib/config.py
  description: Centralized configuration from environment variables. Includes
    BISECT_PRODUCER_QUERY_HOURS, MAX_QUERY_HOURS, WAIT_TASK_QUERY_LIMIT,
    thread counts, producer cycle interval, and feature flags.

lib/repo_manager.py
  path: container/bisect/lib/repo_manager.py
  description: SharedRepoManager — manages pristine bare repo cache and
    workspace clones. Pristine repos use --reference for fast cloning.
    Thread-safe with per-repo locks and clone semaphore. Handles fetch
    refspec configuration for bare repos, periodic cleanup.

lib/bisect_utils.py
  path: container/bisect/lib/bisect_utils.py
  description: Shared utilities. _generate_task_id (deterministic ID from
    error_id), extract_git_url_from_full_text_kv, extract_commit_from_full_text_kv,
    categorize_bisect_task, mark_similar_wait_tasks_for_verification (legacy),
    mark_introduced_errid_tasks_for_verification.

lib/errid_intelligence.py
  path: container/bisect/lib/errid_intelligence.py
  description: Smart error ID filtering. Loads rules from errid_filters.yaml,
    scores error_ids by priority (code errors > warnings > noise), filters
    build tasks by git_url whitelist. Extracts coarse signature for task
    clustering (file_path::error_type).

lib/batch_inserter.py
  path: container/bisect/lib/batch_inserter.py
  description: Batch task creation via ManticoreSearch bulk API. Generates
    deterministic task IDs, attempts bulk insert, falls back to single
    replace on failure. Tracks insert statistics.

lib/task_marking.py
  path: container/bisect/lib/task_marking.py
  description: TaskMarker class — on bisect success, finds other wait tasks
    with same error signature and marks them as "verifying" (result reuse).
    Filters by git_url to prevent cross-repo false matches. Requires file
    path in signature to avoid coarse matches.

lib/producer_reporter.py
  path: container/bisect/lib/producer_reporter.py
  description: Generates structured producer cycle reports. Formats Phase 1-4
    statistics, filtering metrics, dedup rates, system health assessment.
    Also writes JSON analysis files for debugging.

lib/log_config.py
  path: container/bisect/lib/log_config.py
  description: StructuredLogger singleton. Routes logs to per-component
    subdirectories (consumer/, producer/) using pathname-based filters.
    TimedRotatingFileHandler with daily rotation, configurable retention.

lib/query_builder.py
  path: container/bisect/lib/query_builder.py
  description: Query-parameter adapter for list/reset/delete APIs. Converts
    Flask request args into SQL WHERE clauses and concise filter summaries
    consumed by app/controllers.py before execution via ManticoreClient.

lib/notification_writer.py
  path: container/bisect/lib/notification_writer.py
  description: Writes notification files when bisect finds a regression.
    Output consumed by external notification systems (email, webhook).

lib/daily_task_tracker.py
  path: container/bisect/lib/daily_task_tracker.py
  description: Tracks daily task creation/completion counts. Provides
    statistics for monitoring task throughput over time.

lib/lru_cache.py
  path: container/bisect/lib/lru_cache.py
  description: Thread-safe LRU cache with TTL expiration. Used for
    caching job info, commit lookups, and processed task dedup.
```

## API (`app/`)

```
app/__init__.py
  path: container/bisect/app/__init__.py
  description: Flask app factory. Creates app, registers routes, initializes
    TaskProcessor singleton.

app/routes.py
  path: container/bisect/app/routes.py
  description: Flask route definitions. Maps URL paths to controller functions.

app/controllers.py
  path: container/bisect/app/controllers.py
  description: Request handlers. Task submission, status query, manual producer
    trigger, task statistics, verifying task cleanup.

app/submit_tasks_api.py
  path: container/bisect/app/submit_tasks_api.py
  description: Dedicated task submission endpoint. Validates input, calls
    TaskProcessor.add_bisect_task_batch().

app/config.py
  path: container/bisect/app/config.py
  description: Flask app configuration (debug mode, host, port).
```

## Validators (`validators/`)

```
validators/success_task_validator.py
  path: container/bisect/validators/success_task_validator.py
  description: SuccessTaskValidator — processes tasks in "success" status.
    Submits verification jobs to re-run the failing test at first_bad_commit.
    Batch processes by repo to share cloned workspace. Handles verification
    result callbacks (pass → regression record, fail → retry).

validators/head_validator.py
  path: container/bisect/validators/head_validator.py
  description: HEAD regression detection (currently disabled). Checks if
    regressions found by bisect still exist on the latest HEAD commit.

validators/task_optimizer.py
  path: container/bisect/validators/task_optimizer.py
  description: Task scheduling optimization. Priority-based ordering,
    resource-aware scheduling for concurrent bisect tasks.
```

## Commit Time Service (`services/commit_time_service/`)

Standalone HTTP microservice for git commit metadata queries.
Runs as a separate supervisord process on port 8765.

```
services/commit_time_service/server.py
  path: container/bisect/services/commit_time_service/server.py
  description: HTTP server (BaseHTTPRequestHandler). Endpoints: commit/time,
    commit/check (age), commit/is-ancestor, commit/parent, batch_check,
    batch_is_ancestor. Caches results, tracks request stats.

services/commit_time_service/client.py
  path: container/bisect/services/commit_time_service/client.py
  description: Client library for the commit time service. Used by producer
    to check commit age, ancestry, and branch version. Supports batch
    operations. Graceful degradation (returns None on failure).

services/commit_time_service/commit_query.py
  path: container/bisect/services/commit_time_service/commit_query.py
  description: Git operations layer. Runs git commands on pristine bare repos
    to resolve commit timestamps, ancestry (merge-base --is-ancestor),
    parent commits, and base tags. Auto-fetches on cache miss.

services/commit_time_service/cache.py
  path: container/bisect/services/commit_time_service/cache.py
  description: In-memory LRU cache for commit time service. Keyed by
    (git_url, commit_hash), TTL-based expiration.
```

## Scripts (`scripts/`)

```
scripts/debug_pagination.py
  path: container/bisect/scripts/debug_pagination.py
  description: Debug tool — validates pagination query behavior against
    ManticoreSearch. Checks field names, id types, page overlap.

scripts/cleanup_duplicates.py
  path: container/bisect/scripts/cleanup_duplicates.py
  description: One-off script to remove duplicate bisect records from
    ManticoreSearch index.

scripts/diagnose_midpoint_diff.py
  path: container/bisect/scripts/diagnose_midpoint_diff.py
  description: Debug tool — analyzes midpoint divergence in bisect algorithm
    when git bisect and manual calculation disagree.

scripts/migrate_first_bad_commit.py
  path: container/bisect/scripts/migrate_first_bad_commit.py
  description: Migration script — moves first_bad_commit from j field to
    top-level column in bisect index.
```

## Metrics (`metrics/`)

```
metrics/performance_metrics.py
  path: container/bisect/metrics/performance_metrics.py
  description: Performance metric collection. Tracks bisect execution time,
    repo clone duration, task throughput.
```

## Other Services

```
services/pool_monitor_service.py
  path: container/bisect/services/pool_monitor_service.py
  description: Repository pool health monitor. Reports pristine repo count,
    disk usage, stale workspace detection.
```

## Configuration

```
config/errid_filters.yaml
  path: container/bisect/config/errid_filters.yaml
  description: Error ID filtering rules. Blacklist patterns (noise),
    whitelist patterns (high-value), kernel repo allowlist, priority scores.

config/supervisord.conf
  path: container/bisect/config/supervisord.conf
  description: Process manager config. Runs commit-time-service and flask-api
    as managed processes with log routing to subdirectories.
```

## External dependency (lkp-tests)

```
lkp-tests/sbin/bisect/lkp_bisect/db/manticore.py
  description: ManticoreClient — low-level ManticoreSearch client used by all
    bisect components. Provides insert/replace/update/search/sql_select/batch_insert.
    See lkp-tests/sbin/bisect/CODEBASE.md for full lkp-tests bisect docs.
```
