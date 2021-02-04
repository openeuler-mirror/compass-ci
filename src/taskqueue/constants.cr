# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

TASKQUEUE_PORT = 3060

QUEUE_NAME_BASE = "queues"

REDIS_HOST     = "172.17.0.1"
REDIS_PORT     = 6379

# delimiter and exttract-ststs will loop consume job
# when use 32 (scheduler use 25), meet Exception:
#   Exception: No free connection (used 32 of 32)
REDIS_POOL_NUM =   1000

REDIS_POOL_TIMEOUT = 10 # ms

HTTP_MAX_TIMEOUT     = 57000 # less to 1 minute (most http longest timeout)

# redis-benchmark: 100000 request in 1.88 seconds (0.0188ms/each)
#   so we use 0.015ms for timeout, means no retry at default
HTTP_DEFAULT_TIMEOUT = 0.015
