"""Environment-backed configuration schema and defaults for bisect runtime."""

import os

class Config:
    PORT = int(os.environ.get('BISECT_API_PORT', 9999))
    MANTICORE_HOST = os.environ.get('MANTICORE_HOST', 'localhost')
    MANTICORE_PORT = int(os.environ.get('MANTICORE_PORT', 9308))
    BISECT_MODE = os.environ.get('bisect_mode', 'local')
    LKP_SRC = os.environ.get('LKP_SRC', '/c/lkp-tests')
    CCI_SRC = os.environ.get('CCI_SRC', '/c/compass-ci')
    CI_CONFIG_PATH = os.environ.get(
        'CI_CONFIG_PATH',
        os.path.join(
            os.environ.get('LKP_SRC', '/c/lkp-tests'),
            'sbin/bisect/kernel_ci/ci_config.yaml'
        )
    )

    # Thread pool configuration
    # Default: 32 threads, can be increased since workspace overhead is low (~90MB per thread)
    # Workspace usage: 32 threads * 90MB ≈ 2.8GB, pristine repos dominate disk usage
    BISECT_THREADS = int(os.environ.get('BISECT_THREADS', 32))
    MAX_THREADS = 64  # Safety limit to prevent resource exhaustion

    # Producer switch configuration
    BISECT_PRODUCER_ENABLED = os.environ.get('BISECT_PRODUCER_ENABLED', 'true').lower() == 'true'

    # Task deduplication configuration
    BISECT_DEDUPE_BY_ERRID = os.environ.get('BISECT_DEDUPE_BY_ERRID', 'true').lower() == 'true'

    # Producer cycle interval configuration (hours)
    BISECT_PRODUCER_CYCLE_HOURS = int(os.environ.get('BISECT_PRODUCER_CYCLE_HOURS', 6))

    # Producer scheduled execution configuration
    BISECT_PRODUCER_SCHEDULED_ENABLED = os.environ.get('BISECT_PRODUCER_SCHEDULED_ENABLED', 'true').lower() == 'true'
    BISECT_PRODUCER_SCHEDULED_TIME = os.environ.get('BISECT_PRODUCER_SCHEDULED_TIME', '22:00') # HH:MM format

    # Producer query time range configuration (hours)
    # How many hours of historical data to query
    # 25 hours = daily run + 1 hour overlap for fault tolerance
    # TODO: temporarily set to 720 for backlog catch-up, revert to 25 after testing
    BISECT_PRODUCER_QUERY_HOURS = int(os.environ.get('BISECT_PRODUCER_QUERY_HOURS', 48))

    # Adaptive query window: max hours the producer can expand to when catching up on backlog
    # When a cycle creates new tasks, the next cycle doubles the window (up to this cap)
    # When no new tasks are found, the window resets to BISECT_PRODUCER_QUERY_HOURS
    # Set to same as BISECT_PRODUCER_QUERY_HOURS to disable adaptive expansion
    BISECT_PRODUCER_MAX_QUERY_HOURS = int(os.environ.get('BISECT_PRODUCER_MAX_QUERY_HOURS', 720))

    # Producer batch configuration
    BISECT_PRODUCER_BATCH_SIZE = int(os.environ.get('BISECT_PRODUCER_BATCH_SIZE', 50))

    # Error ID printing configuration
    ERROR_ID_MAX_PER_LINE = int(os.environ.get('ERROR_ID_MAX_PER_LINE', 5))
    ERROR_ID_MAX_LENGTH = int(os.environ.get('ERROR_ID_MAX_LENGTH', 80))

    # Notification directory configuration
    NOTIFICATION_DIR = os.environ.get('BISECT_NOTIFICATION_DIR', '/result/bisect/notifications')
    NOTIFICATION_WEBHOOK_URL = os.environ.get('BISECT_NOTIFICATION_WEBHOOK_URL', '')
    NOTIFICATION_EMAIL = os.environ.get('BISECT_NOTIFICATION_EMAIL', '')

    # Verification configuration
    PARALLEL_VERIFICATION_JOBS = int(os.environ.get('PARALLEL_VERIFICATION_JOBS', 200))
    VERIFICATION_BATCH_SIZE = int(os.environ.get('VERIFICATION_BATCH_SIZE', 200))
    VALIDATION_INTERVAL = int(os.environ.get('VALIDATION_INTERVAL', 60))
    MAX_VERIFYING_TASKS = int(os.environ.get('MAX_VERIFYING_TASKS', 10))
    VERIFICATION_TIMEOUT_HOURS = int(os.environ.get('VERIFICATION_TIMEOUT_HOURS', 24))
    VERIFICATION_TIMEOUT_RETRY_MAX = int(os.environ.get('VERIFICATION_TIMEOUT_RETRY_MAX', 2))
    VERIFICATION_TIMEOUT_FINAL_ACTION = os.environ.get(
        'VERIFICATION_TIMEOUT_FINAL_ACTION', 'rebisect'
    ).lower()

    # HEAD check configuration
    HEAD_CHECK_BATCH_SIZE = int(os.environ.get('HEAD_CHECK_BATCH_SIZE', 200))
    HEAD_CHECK_INTERVAL = int(os.environ.get('HEAD_CHECK_INTERVAL', 86400))
    HEAD_VALIDATOR_ENABLED = os.environ.get('BISECT_HEAD_VALIDATOR_ENABLED', 'true').lower() == 'true'

    # Repository clone concurrency control
    # Shared by all consumers (BisectConsumer, SuccessTaskValidator, HeadValidator)
    # Validators only do lightweight git operations (rev-parse), not checkout
    BISECT_MAX_CONCURRENT_CLONES = int(os.environ.get('BISECT_MAX_CONCURRENT_CLONES', 4))

    # Git clone timeout configuration (in seconds)
    # For pristine repository clone (full clone without --reference)
    GIT_CLONE_PRISTINE_TIMEOUT = int(os.environ.get('GIT_CLONE_PRISTINE_TIMEOUT', 3600))  # 60 minutes
    # For workspace clone (with --reference, should be faster but may still timeout on HDD)
    GIT_CLONE_WORKSPACE_TIMEOUT = int(os.environ.get('GIT_CLONE_WORKSPACE_TIMEOUT', 3600))  # 60 minutes

    # Pristine repository fetch interval (in seconds)
    # How often to fetch updates for pristine repos
    # Default: 3600 (1 hour) - pristine doesn't need to be real-time latest
    # Set to 86400 (24 hours) for daily updates if desired
    GIT_PRISTINE_FETCH_INTERVAL = int(os.environ.get('GIT_PRISTINE_FETCH_INTERVAL', 3600))

    # Repository pool configuration (for HDD optimization)
    # Maximum number of instances per repository name (e.g., linux-1, linux-2, ...)
    # CRITICAL: Must accommodate worst-case scenario where all concurrent tasks use same repo
    #
    # Calculation:
    #   - BISECT_THREADS: 32-128 concurrent bisect tasks
    #   - VERIFICATION_BATCH_SIZE: 200 tasks processed in parallel
    #   - Worst case: all tasks target same repo (e.g., openeuler-kernel)
    #   - Recommendation: Set to max(BISECT_THREADS, VERIFICATION_BATCH_SIZE) + buffer
    #
    # Current setting: 150 instances/repo (increased from 64)
    #   - Covers BISECT_THREADS (up to 128) + VERIFICATION concurrent (20-30) + buffer
    #   - Per-repo limit, so multiple repos don't compete
    #   - Disk usage: ~150 * 90MB = 13.5GB per active repository (workspace only)
    REPO_POOL_MAX_INSTANCES = int(os.environ.get('REPO_POOL_MAX_INSTANCES', 150))
    # Timeout in seconds when waiting for available repository instance
    # Increased from 3600s (1h) to 28800s (8h) to accommodate slower bisect tasks
    REPO_POOL_ACQUIRE_TIMEOUT = int(os.environ.get('REPO_POOL_ACQUIRE_TIMEOUT', 28800))
    # Enable repository cleanup on return (git reset + clean)
    REPO_POOL_CLEANUP_ON_RETURN = os.environ.get('REPO_POOL_CLEANUP_ON_RETURN', 'true').lower() == 'true'
    # Enable repository health check on return
    REPO_POOL_HEALTH_CHECK = os.environ.get('REPO_POOL_HEALTH_CHECK', 'true').lower() == 'true'
    # Enable repository sync (git fetch) on return
    REPO_POOL_SYNC_ON_RETURN = os.environ.get('REPO_POOL_SYNC_ON_RETURN', 'true').lower() == 'true'

    # Task reuse confidence threshold configuration
    # Only reuse success tasks with this confidence level or higher
    # Valid values: 'high', 'medium', 'low'
    # Default: 'high' (only reuse high-confidence tasks)
    TASK_REUSE_MIN_CONFIDENCE = os.environ.get('TASK_REUSE_MIN_CONFIDENCE', 'high').lower()

    # Kernel version filtering configuration
    # Minimum kernel version for bisect (filter out commits on older branches)
    # Format: "major.minor" (e.g., "5.10", "6.1")
    # Commits based on older kernel versions (e.g., v4.9.x) will be filtered out
    # Set to empty string "" to disable version filtering
    BISECT_MIN_KERNEL_VERSION = os.environ.get('BISECT_MIN_KERNEL_VERSION', '5.10')

    # Maximum commit age in days for bisect
    BISECT_MAX_COMMIT_AGE_DAYS = int(os.environ.get('BISECT_MAX_COMMIT_AGE_DAYS', 365))

    # ====== Performance Producer Configuration ======
    # Enable/disable performance bisect producer
    PERFORMANCE_PRODUCER_ENABLED = os.environ.get('PERFORMANCE_PRODUCER_ENABLED', 'true').lower() == 'true'

    # Query time range in hours for performance jobs
    # 25 hours = daily run + 1 hour overlap for fault tolerance
    PERFORMANCE_PRODUCER_QUERY_HOURS = int(os.environ.get('PERFORMANCE_PRODUCER_QUERY_HOURS', 25))

    # Wider query windows for performance bisect comparison pairs
    # Baseline: 30 days (720h) — stable tags, old results remain valid
    BASELINE_QUERY_HOURS = int(os.environ.get('BASELINE_QUERY_HOURS', 720))
    # Current: 14 days (336h) — RC tags rotate weekly, 14 days gives ~14 samples per suite
    CURRENT_QUERY_HOURS = int(os.environ.get('CURRENT_QUERY_HOURS', 336))

    # Producer interval in days (run once per day)
    PERFORMANCE_PRODUCER_INTERVAL_DAYS = int(os.environ.get('PERFORMANCE_PRODUCER_INTERVAL_DAYS', 1))

    # Minimum samples required per version for valid comparison
    PERFORMANCE_MIN_SAMPLES = int(os.environ.get('PERFORMANCE_MIN_SAMPLES', 2))

    # Default sample count target per version
    PERFORMANCE_DEFAULT_SAMPLES = int(os.environ.get('PERFORMANCE_DEFAULT_SAMPLES', 3))

    # Performance test suites to monitor (comma-separated)
    PERFORMANCE_SUITES = os.environ.get(
        'PERFORMANCE_SUITES',
        'unixbench,lmbench,iozone,fio,filebench,stream,hackbench,netperf,sysbench,sysbench-cpu,sysbench-memory,sysbench-mutex,sysbench-threads,stress-ng'
    )

    # : performance_metrics.yaml configfile
    #  lkp-stats-type.md  KPI 
    # KPI :  (LAT, RATE, JIT, POW, COST, MEM)
    # : lat/jit/pow/cost/mem = -1 (SmallerBetter), rate = +1 (BiggerBetter)

    # ====== SQL Query Configuration ======
    # Default limit for list queries
    DEFAULT_QUERY_LIMIT = int(os.environ.get('DEFAULT_QUERY_LIMIT', 100000))
    # Maximum allowed query limit
    MAX_QUERY_LIMIT = int(os.environ.get('MAX_QUERY_LIMIT', 1000000))
    # Batch size for delete operations
    BATCH_DELETE_SIZE = int(os.environ.get('BATCH_DELETE_SIZE', 500))
    # Maximum valid 64-bit signed integer (for task ID validation)
    MAX_INT64 = 2**63 - 1

    # Limit for querying wait tasks (used by signature matching and errid reuse)
    WAIT_TASK_QUERY_LIMIT = int(os.environ.get('WAIT_TASK_QUERY_LIMIT', 5000))
