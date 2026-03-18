# Issue: Repo and Lock Logic Review

## Scope

Review repository lifecycle and lock/concurrency behavior in:

- `container/bisect/lib/repo_manager.py`
- `container/bisect/core/task_processor.py`
- `container/bisect/services/commit_time_service/commit_query.py`
- `container/bisect/config/supervisord.conf`

## Findings

### 1) High: Locks are thread-local, not process-safe

Current locking uses in-process primitives (`threading.Lock`, `threading.Semaphore`) in `SharedRepoManager`.
However, `supervisord` runs multiple processes (`commit-time-service`, `flask-api`), each with its own
`SharedRepoManager` instance. This means there is no cross-process exclusion for operations on shared pristine
repo paths.

Impact:
- Concurrent clone/fetch/update of the same pristine repo can race across processes.
- Potential repo corruption or transient failures under load.

### 2) High: Lock key and repo path key mismatch (`repo_url` vs `repo_name`)

Pristine path is derived from `repo_name`, but lock/timestamp maps are keyed by raw `repo_url`.
Different URL forms for the same repo (for example, `git+https://...` vs `https://...`) can map to the same
directory while acquiring different locks.

Impact:
- Parallel operations can bypass expected mutual exclusion.
- Fetch throttling (`PRISTINE_FETCH_INTERVAL`) can be bypassed.

### 3) Medium: Stale lock cleanup may unlock active tasks

`_cleanup_stale_locks()` removes lock entries when task status is `wait`. During edge timing windows, a task may
still be in-flight while DB status has not yet transitioned, and lock removal can permit duplicate submission.

Impact:
- Duplicate task execution.
- Unnecessary work and harder-to-debug race behavior.

### 4) Medium: Commit-time fetch path logs success even on fetch failure

In `commit_query._fetch_pristine_repo()`, `subprocess.run` does not check return code and logs fetched-success
unconditionally.

Impact:
- False-positive logs.
- Hidden stale state and confusing behavior during retry/lock contention.

### 5) Low: Dynamic SQL `IN (...)` built via string join

`task_processor._cleanup_stale_locks()` builds `WHERE id IN (...)` by direct string interpolation.

Impact:
- Fragile query construction.
- Harder to harden/maintain safely.

## Recommended Fix Plan

1. Add cross-process file lock for pristine repo operations:
   - per-repo lock file under pristine root (for example `<pristine_repo_dir>/.repo.lock`)
   - use `fcntl.flock` around clone/fetch/recreate critical sections
2. Canonicalize repo key before lock/timestamp lookup:
   - normalize URL (`git+http(s)` stripping, trailing slash normalization, optional `.git` normalization)
   - key lock/timestamp maps with canonical key or `repo_name` consistently
3. Tighten stale-lock policy:
   - do not clear `wait` locks immediately; require age threshold or owner heartbeat
   - keep cleanup focused on terminal/not-found states
4. Make fetch execution strict:
   - use `check=True` or verify `returncode`
   - log success only on real success, otherwise warn/error and propagate as needed
5. Harden status query path:
   - ensure IDs are numeric before join
   - or switch to safer query composition supported by client

## Validation Checklist

- Concurrent stress test with both `flask-api` and `commit-time-service` active:
  - no pristine repo corruption
  - no duplicate clone/fetch race errors
- Task queue stress:
  - no duplicate processing due to stale-lock cleanup
- Log correctness:
  - fetch success/failure logs reflect actual subprocess outcome
- Regression:
  - non-integration tests pass
  - integration tests pass in localhost-enabled runtime
