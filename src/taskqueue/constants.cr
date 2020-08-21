# SPDX-License-Identifier: MulanPSL-2.0+

TASKQUEUE_PORT = 3060

QUEUE_NAME_BASE = "queues"

REDIS_HOST = "172.17.0.1"
REDIS_PORT = 6379
REDIS_POOL_NUM = 32 # when use 16 (scheduler use 25), meet Exception:
                    #   Exception: No free connection (used 16 of 16)

REDIS_POOL_TIMEOUT = 10  # ms

HTTP_MAX_TIMEOUT = 57000     # less to 1 minute (most http longest timeout)
HTTP_DEFAULT_TIMEOUT = 1     # 1ms (less than redis timeout, that's no retry)
