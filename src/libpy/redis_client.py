import os
from rediscluster import RedisCluster

from src.libpy.constants import REDIS_HOST, REDIS_PORT


class RedisClient:
    def __init__(self):
        startup_nodes = [{"host": REDIS_HOST, "port": REDIS_PORT}]
        self.client = RedisCluster(startup_nodes=startup_nodes, decode_responses=True)

    def set(self, key, value):
        return self.client.set(key, value)

    def get(self, key):
        return self.client.get(key)

    def delete(self, key):
        return self.client.delete(key)

    def incr(self, key):
        return self.client.incr(key)

    def hget(self, name, key):
        return self.client.hget(name, key)

    def hset(self, name, key, value):
        return self.client.hset(name, key, value)

    def hgetall(self, key):
        return self.client.hgetall(key)

    def exists(self, name):
        return self.client.exists(name)

    def set_expire(self, name, timeout):
        return self.client.expire(name, timeout)

    def set_add(self, name, *values):
        return self.client.sadd(name, *values)

    def is_set_member(self, name, value):
        return self.client.sismember(name, value)

    def set_remove(self, name, *values):
        return self.client.srem(name, *values)

    def get_match_keys(self, match):
        return self.client.scan_iter(match)
