import os

from etcd3 import Etcd3Client, etcdrpc, utils, client, events

from src.libpy.constants import ETCD_HOST, ETCD_PORT


class _Etcd3ClientPatch(object):
    def build_get_range_request(self, key,
                                range_end=None,
                                limit=None,
                                sort_order=None,
                                sort_target='key',
                                serializable=False,
                                keys_only=False,
                                min_create_revision=None):
        range_request = etcdrpc.RangeRequest()
        range_request.key = utils.to_bytes(key)
        range_request.keys_only = keys_only
        if range_end is not None:
            range_request.range_end = utils.to_bytes(range_end)
        if limit is not None:
            range_request.limit = limit
        if min_create_revision is not None:
            range_request.min_mod_revision = min_create_revision

        if sort_order is None:
            range_request.sort_order = etcdrpc.RangeRequest.NONE
        elif sort_order == 'ascend':
            range_request.sort_order = etcdrpc.RangeRequest.ASCEND
        elif sort_order == 'descend':
            range_request.sort_order = etcdrpc.RangeRequest.DESCEND
        else:
            raise ValueError('unknown sort order: "{}"'.format(sort_order))

        if sort_target is None or sort_target == 'key':
            range_request.sort_target = etcdrpc.RangeRequest.KEY
        elif sort_target == 'version':
            range_request.sort_target = etcdrpc.RangeRequest.VERSION
        elif sort_target == 'create':
            range_request.sort_target = etcdrpc.RangeRequest.CREATE
        elif sort_target == 'mod':
            range_request.sort_target = etcdrpc.RangeRequest.MOD
        elif sort_target == 'value':
            range_request.sort_target = etcdrpc.RangeRequest.VALUE
        else:
            raise ValueError('sort_target must be one of "key", '
                             '"version", "create", "mod" or "value"')

        range_request.serializable = serializable

        return range_request


# 动态替换实现，支持limit和min_create_revision
Etcd3Client._build_get_range_request = _Etcd3ClientPatch.build_get_range_request


class EtcdClient:
    def __init__(self):
        self.client = client(host=ETCD_HOST, port=ETCD_PORT,
                user=os.getenv("ETCD_USER"), password=os.getenv("ETCD_PASSWORD"))

    def get_prefix(self, key_prefix, *args, **kwargs):
        return self.client.get_prefix(key_prefix, *args, **kwargs)

    def get(self, key):
        return self.client.get(key)

    def put(self, key, value):
        return self.client.put(key, value)

    def delete(self, key):
        return self.client.delete(key)

    def watch_rpmbuild(self, start_revision=None):
        return self.client.watch_prefix("update_jobs/", start_revision=start_revision)

    @staticmethod
    def is_delete_event(event):
        return isinstance(event, events.DeleteEvent)

    def watch_prefix(self, prefix_key, start_revision=None):
        return self.client.watch_prefix(prefix_key, start_revision=start_revision)
