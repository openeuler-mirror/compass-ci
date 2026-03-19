# Bisect Testing Guide

## Quick start — run unit tests

```bash
cd container/bisect

# Commit time service tests (fast, no external deps)
PYTHONPATH=lib:services/commit_time_service:. \
  python3 -m pytest services/commit_time_service/tests/ -v

# Core tests
PYTHONPATH=lib:core:services/commit_time_service:. \
  python3 -m pytest core/tests/ -v
```

## One-command functional test (CI friendly)

Run from repository root:

```bash
bash container/bisect/scripts/run_functional_tests.sh
```

Notes:
- By default this runs compile checks + non-integration test suites only.
- To include integration tests (opens localhost service socket), set:

```bash
RUN_INTEGRATION=1 bash container/bisect/scripts/run_functional_tests.sh
```

## Test locations

| Test | What it covers |
|------|---------------|
| `services/commit_time_service/tests/test_commit_query.py` | is_ancestor, commit timestamps, error handling |
| `services/commit_time_service/tests/test_is_ancestor.py` | Client + server is_ancestor, batch operations |
| `services/commit_time_service/tests/test_cache.py` | LRU cache TTL and eviction |
| `core/tests/test_load_baseline_commits.py` | Performance producer baseline loading |

## Post-deploy validation

After deploying code changes to the container, follow these steps to verify.
See [TESTING_GUIDE.md](TESTING_GUIDE.md) for detailed commands and expected output.

### 1. Verify code is deployed

```bash
docker exec bisect grep "YOUR_CHANGE_KEYWORD" /c/compass-ci/container/bisect/core/bisect_producer.py
docker restart bisect
```

### 2. Check startup

```bash
docker exec bisect tail -20 /result/bisect/logs/consumer/consumer.log
# Should show: "Container startup reset completed" and thread initialization
```

### 3. Test producer

```bash
# Trigger manually or wait for scheduled cycle
curl -X POST http://localhost:9999/trigger_producer

# Check output
docker exec bisect tail -50 /result/bisect/logs/producer/producer.log
```

Key checkpoints:
- `Queried jobs: N` — should be > 1000 with pagination
- `Phase 0 completed: collected N valid jobs` — N > 0
- `Phase 4 prep: X entries, Y unique error_ids | expected new: Z`

### 4. Test consumer

```bash
docker exec bisect grep "Start processing task\|Task completed\|Task failed" \
  /result/bisect/logs/consumer/consumer.log | tail -10
```

### 5. Test commit time service

```bash
docker exec bisect curl -s http://localhost:8765/health
docker exec bisect curl -s http://localhost:8765/api/v1/stats
```

### 6. Verify ManticoreSearch queries

```bash
# Confirm max_matches works (result > 1000 means pagination/max_matches is correct)
docker exec bisect python3 /c/compass-ci/container/bisect/scripts/debug_pagination.py
```

## Adding new tests

1. Create `test_*.py` in the appropriate `tests/` directory
2. Use `unittest` or `pytest` conventions
3. Set environment variables in test setup:
   ```python
   os.environ['CCI_SRC'] = '/srv/cci'
   os.environ['WORK_DIR'] = '/tmp'
   os.environ['LKP_SRC'] = '/srv/lkp'
   ```
4. Run: `PYTHONPATH=lib:services/commit_time_service:. python3 -m pytest path/to/test.py -v`

## Common issues

| Problem | Solution |
|---------|----------|
| `ModuleNotFoundError` | Set `PYTHONPATH=lib:core:services/commit_time_service:.` |
| `Connection refused` to ManticoreSearch | Tests use mocks; integration tests need `MANTICORE_HOST` |
| Stale cache masking changes | Restart container to clear `processed_jobs_cache` |

## Documentation hygiene checks

Run these checks after doc/translation updates:

```bash
# 1) Verify no Chinese text in bisect Python modules
python3 - <<'PY'
import pathlib, re
root = pathlib.Path("container/bisect")
han = re.compile(r"[\\u4e00-\\u9fff]")
hits = [p for p in root.rglob("*.py") if han.search(p.read_text(errors="ignore"))]
print(f"python files with Chinese text: {len(hits)}")
for p in hits:
    print(p)
PY

# 2) Verify module-level docstrings are present
python3 - <<'PY'
import ast, pathlib
root = pathlib.Path("container/bisect")
missing = []
for p in root.rglob("*.py"):
    try:
        m = ast.parse(p.read_text(errors="ignore"))
    except Exception:
        continue
    if ast.get_docstring(m, clean=False) is None:
        missing.append(p)
print(f"missing module docstrings: {len(missing)}")
for p in missing:
    print(p)
PY
```

## Clone benchmark (performance tuning)

For tuning `BISECT_MAX_CONCURRENT_CLONES`:

```bash
cd scripts/
./benchmark_clones_quick.py                    # Quick test with small repo
./benchmark_clones_quick.py --repo https://gitee.com/openeuler/kernel.git  # Real repo
```

Choose the concurrency level with highest throughput while keeping tmpfs usage under 70%.
