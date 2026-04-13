# Bisect Service — Document Index

Quick reference to all documentation, code maps, and issue trackers.

## For newcomers

| Doc | What it covers |
|-----|---------------|
| [README.md](../README.md) | Deployment, configuration, API usage, troubleshooting |
| [docs/CODEBASE.md](CODEBASE.md) | Code map — every file's path and purpose, architecture diagram |
| [docs/DESIGN.md](DESIGN.md) | Architecture deep dive — task lifecycle, verification, repo pooling |
| [docs/ALGORITHM.md](ALGORITHM.md) | Bisect algorithm specification |

## For developers

| Doc | What it covers |
|-----|---------------|
| [docs/CODEBASE.md](CODEBASE.md) | File inventory with descriptions, data flow diagram |
| [docs/TESTING.md](TESTING.md) | How to test — unit tests, post-deploy validation, producer/consumer verification |
| [docs/API_DOCUMENTATION.md](API_DOCUMENTATION.md) | REST API endpoints, examples, verification queue status API |
| [docs/DATA_BASE.md](DATA_BASE.md) | ManticoreSearch schema — bisect/jobs/regression indexes |
| [docs/PERFORMANCE_BISECT_DESIGN.md](PERFORMANCE_BISECT_DESIGN.md) | Performance regression bisect specifics |

## Database access boundary

There are two database-related layers in the bisect service, with different roles:

| Layer | Path | Responsibility |
|------|------|----------------|
| DB client | `lkp-tests/sbin/bisect/lkp_bisect/db/manticore.py` | `ManticoreClient` executes SQL against ManticoreSearch |
| Query helper | `container/bisect/lib/query_builder.py` | Converts HTTP query params into SQL `WHERE` clauses and concise filter summaries |

The typical request path is:

`sbin/bisect_api.py` -> Flask route -> `app/controllers.py` -> `lib/query_builder.py` -> `ManticoreClient`

## Configuration

| File | Purpose |
|------|---------|
| `config/errid_filters.yaml` | Error ID filtering rules (blacklist, whitelist, priority scores) |
| `config/supervisord.conf` | Process manager — flask-api, commit-time-service |
| `lib/config.py` | All environment variable defaults and feature flags, including verification queue limits |
| `Dockerfile` | Container build definition |
| `start` | Container launch script (volume mounts, env vars) |

## Issue tracking

| Issue | Status |
|-------|--------|
| [issues/config-reload-boundary.md](../issues/config-reload-boundary.md) | IN PROGRESS — inventory complete, hot-reload follow-up pending |
| [issues/bisect-api-cli-issues.md](../issues/bisect-api-cli-issues.md) | DONE — bisect_api.py CLI/API mismatches fixed and tests added |
| [issues/chinese-to-english-translation.md](../issues/chinese-to-english-translation.md) | DONE — Chinese text scan reports 0 Python files |
| [issues/missing-docstrings.md](../issues/missing-docstrings.md) | DONE — module docstring scan reports 0 missing |

## Claude Code skills

Located in `~/.claude/skills/`, usable from any machine with Claude Code:

| Skill | Trigger |
|-------|---------|
| `analyze-bisect-log` | Analyze producer/consumer log output |
| `diagnose-stuck-tasks` | Query ManticoreSearch for stuck tasks |
| `review-bisect-changes` | Pre-deploy checklist (max_matches, j-field merge, etc.) |
| `check-manticore-query` | Validate ManticoreSearch query correctness |

## External dependencies

| Repo | Path | What |
|------|------|------|
| lkp-tests | `sbin/bisect/lkp_bisect/db/manticore.py` | ManticoreClient — DB access layer |
| lkp-tests | `programs/bisect-py/` | Bisect execution scripts (git bisect run) |
| lkp-tests | `sbin/bisect/CODEBASE.md` | lkp-tests bisect code map |

## Log file structure (inside container)

```
/result/bisect/logs/
├── consumer/          # Consumer, validator, task_processor
│   ├── consumer.log
│   └── error.log
├── producer/          # Producer cycles
│   ├── producer.log
│   └── error.log
├── api/               # Flask REST API (supervisord)
│   ├── api.log
│   └── error.log
├── commit-service/    # Commit time service (supervisord)
│   ├── service.log
│   └── error.log
└── performance/       # Performance metrics
    └── performance.log
```
