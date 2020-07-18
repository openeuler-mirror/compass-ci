TASKQUEUE_PORT = 3060

QUEUE_NAME_BASE = "queues"

REDIS_HOST = "172.17.0.1"
REDIS_PORT = 6379
REDIS_POOL_NUM = 16

HTTP_MAX_TIMEOUT = 57000     # less to 1 minute (most http longest timeout)
HTTP_DEFAULT_TIMEOUT = 300   # 300ms (try every 5ms, that's 60 times of try)
