import os

class Config:
    PORT = int(os.environ.get('BISECT_API_PORT', 9999))
    MANTICORE_HOST = os.environ.get('MANTICORE_HOST', 'localhost')
    MANTICORE_PORT = int(os.environ.get('MANTICORE_PORT', 9308))
    BISECT_MODE = os.environ.get('bisect_mode', 'local')
    LKP_SRC = os.environ.get('LKP_SRC', '/c/lkp-tests')
    CCI_SRC = os.environ.get('CCI_SRC', '/c/compass-ci')

    # Thread pool configuration
    BISECT_THREADS = int(os.environ.get('BISECT_THREADS', 32))
    MAX_THREADS = min(64, os.cpu_count() * 4)  # No more than 64 threads

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
    BISECT_PRODUCER_QUERY_HOURS = int(os.environ.get('BISECT_PRODUCER_QUERY_HOURS', 25))

    # Producer batch configuration
    BISECT_PRODUCER_BATCH_SIZE = int(os.environ.get('BISECT_PRODUCER_BATCH_SIZE', 50))

    # Error ID printing configuration
    ERROR_ID_MAX_PER_LINE = int(os.environ.get('ERROR_ID_MAX_PER_LINE', 5))
    ERROR_ID_MAX_LENGTH = int(os.environ.get('ERROR_ID_MAX_LENGTH', 80))

    # Notification directory configuration
    NOTIFICATION_DIR = os.environ.get('BISECT_NOTIFICATION_DIR', '/result/bisect/notifications')

    # Verification configuration
    PARALLEL_VERIFICATION_JOBS = int(os.environ.get('PARALLEL_VERIFICATION_JOBS', 200))
    VERIFICATION_BATCH_SIZE = int(os.environ.get('VERIFICATION_BATCH_SIZE', 200))

    # HEAD check configuration
    HEAD_CHECK_BATCH_SIZE = int(os.environ.get('HEAD_CHECK_BATCH_SIZE', 200))

    # Repository clone concurrency control
    # Shared by all consumers (BisectConsumer, SuccessTaskValidator, HeadValidator)
    # Validators only do lightweight git operations (rev-parse), not checkout
    BISECT_MAX_CONCURRENT_CLONES = int(os.environ.get('BISECT_MAX_CONCURRENT_CLONES', 4))

    # Git clone timeout configuration (in seconds)
    # For pristine repository clone (full clone without --reference)
    GIT_CLONE_PRISTINE_TIMEOUT = int(os.environ.get('GIT_CLONE_PRISTINE_TIMEOUT', 3600))  # 60 minutes
    # For workspace clone (with --reference, should be faster but may still timeout on HDD)
    GIT_CLONE_WORKSPACE_TIMEOUT = int(os.environ.get('GIT_CLONE_WORKSPACE_TIMEOUT', 3600))  # 60 minutes

    # Repository pool configuration (for HDD optimization)
    # Maximum number of instances per repository name (e.g., linux-1, linux-2, ...)
    # CRITICAL: Must accommodate worst-case scenario where all concurrent tasks use same repo
    #
    # Calculation:
    #   - BISECT_THREADS: 32 concurrent bisect tasks
    #   - VERIFICATION_BATCH_SIZE: 200 tasks processed in parallel
    #   - Worst case: all tasks target same repo (e.g., openeuler-kernel)
    #   - Recommendation: Set to max(BISECT_THREADS, VERIFICATION_BATCH_SIZE) + buffer
    #
    # Current setting: 64 instances/repo
    #   - Covers BISECT_THREADS (32) + VERIFICATION concurrent (20-30) + buffer
    #   - Per-repo limit, so multiple repos don't compete
    #   - Disk usage: ~64 * 5GB = 320GB per active repository
    REPO_POOL_MAX_INSTANCES = int(os.environ.get('REPO_POOL_MAX_INSTANCES', 64))
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
