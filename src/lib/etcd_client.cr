# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "etcd"

require "./constants"

class EtcdClient
  def initialize
    host = (ENV.has_key?("ETCD_HOST") ? ENV["ETCD_HOST"] : ETCD_HOST)
    port = (ENV.has_key?("ETCD_PORT") ? ENV["ETCD_PORT"].to_i32 : ETCD_PORT)
    version = (ENV.has_key?("ETCD_VERSION") ? ENV["ETCD_VERSION"] : ETCD_VERSION)
    @etcd = Etcd.client(host, port, version)
  end

  def close
    @etcd.close
  end

  def put(queue, content)
    queue = "#{BASE}/#{queue}" unless queue.starts_with?(BASE)
    @etcd.kv.put_not_exists(queue, content)
  end

  def delete(queue)
    queue = "#{BASE}/#{queue}" unless queue.starts_with?(BASE)
    @etcd.kv.delete(queue)
  end

  def range(queue)
    queue = "#{BASE}/#{queue}" unless queue.starts_with?(BASE)
    @etcd.kv.range(queue)
  end

  def range_prefix(prefix)
    prefix = "#{BASE}/#{prefix}" unless prefix.starts_with?(BASE)
    @etcd.kv.range_prefix(prefix)
  end

  def update(queue, value)
    queue = "#{BASE}/#{queue}" unless queue.starts_with?(BASE)
    @etcd.kv.put(queue, value)
  end

  def move(f_queue, t_queue, value)
    f_queue = "#{BASE}/#{f_queue}" unless f_queue.starts_with?(BASE)
    t_queue = "#{BASE}/#{t_queue}" unless t_queue.starts_with?(BASE)
    @etcd.kv.move(f_queue, t_queue, value)
  end

  def move(f_queue, t_queue)
    f_queue = "#{BASE}/#{f_queue}" unless f_queue.starts_with?(BASE)
    t_queue = "#{BASE}/#{t_queue}" unless t_queue.starts_with?(BASE)
    res = range(f_queue)
    raise "can not move the queue in etcd: #{f_queue}" if res.count == 0

    @etcd.kv.move(f_queue, t_queue, res.kvs[0].value)
  end

  def watch_prefix(prefix, **opts, &block : Array(Etcd::Model::WatchEvent) -> Void)
    prefix = "#{BASE}/#{prefix}" unless prefix.starts_with?(BASE)
    @etcd.watch.watch_prefix(prefix, **opts, &block)
  end

  def update_base_version(key, value, version)
    key = "#{BASE}/#{key}" unless key.starts_with?(BASE)
    key = Base64.strict_encode(key)
    value = Base64.strict_encode(value)
    post_body = {
      :compare => [{
        :key => key,
        :version => "#{version}",
        :target => "VERSION",
        :result => "EQUAL",
      }],
      :success =>[{
        :request_put =>{
          :key => key,
          :value => value,
        }
      }],
    }

    response = @etcd.api.post("/kv/txn", post_body)
    Etcd::Model::TxnResponse.from_json(response.body).succeeded
  end
end

