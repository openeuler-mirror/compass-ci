#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'redis'
require 'json'

# used to handle the redis queues
class RedisClient
  RDS_HOST = ENV['REDIS_HOST'] || REDIS_HOST
  RDS_PORT = ENV['REDIS_PORT'] || REDIS_PORT

  def initialize(queue)
    @queue = queue
    @redis = Redis.new('host' => RDS_HOST, 'port' => RDS_PORT)
  end

  def add_hash_key(key, value)
    return false if @redis.hexists @queue, key

    @redis.hset @queue, key, value
    return true
  end

  def delete_hash_key(key)
    @redis.hdel @queue, key
  end

  def delete_queue
    @redis.del @queue
  end

  def reset_hash_key(key, value)
    @redis.hset @queue, key, value
  end

  def search_hash_key(key)
    h_value = @redis.hget @queue, key

    return h_value if h_value
  end

  def search_all_hash_key
    h_values = @redis.hscan_each(@queue).to_h

    return h_values
  end
end
