#!/usr/bin/env bash
set -euo pipefail

# CI-friendly functional test runner for container/bisect.
# Defaults to non-integration checks; enable integration by setting RUN_INTEGRATION=1.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

export PYTHONPATH="container/bisect/lib:container/bisect/services/commit_time_service:container/bisect"
RUN_INTEGRATION="${RUN_INTEGRATION:-0}"

echo "[functional] compile sanity"
python3 -m compileall -q container/bisect

echo "[functional] commit_time_service non-integration tests"
python3 -m pytest \
  container/bisect/services/commit_time_service/tests/ \
  -k "not service_integration" \
  -q

echo "[functional] core tests"
PYTHONPATH="container/bisect/lib:container/bisect/core:container/bisect/services/commit_time_service:container/bisect" \
  python3 -m pytest container/bisect/core/tests/ -q

if [[ "${RUN_INTEGRATION}" == "1" ]]; then
  echo "[functional] integration tests (requires localhost socket access)"
  python3 -m pytest \
    container/bisect/services/commit_time_service/tests/test_service_integration.py \
    -q
else
  echo "[functional] skip integration tests (set RUN_INTEGRATION=1 to enable)"
fi

echo "[functional] completed"
