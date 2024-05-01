# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "redis"
require "redis/cluster"

require "./constants"
require "../lib/job"
require "singleton"

class RedisClient
  class_property :client
  HOST = (ENV.has_key?("REDIS_HOST") ? ENV["REDIS_HOST"] : JOB_REDIS_HOST)
  PORT = (ENV.has_key?("REDIS_PORT") ? ENV["REDIS_PORT"] : JOB_REDIS_PORT).to_i32
  PASSWD = ENV["REDIS_PASSWD"]
  @@size = 25

  def self.instance
    Singleton::Of(self).instance
  end

  def initialize(host = HOST, port = PORT, pool_size = @@size, passwd = PASSWD)
    @client = Redis::Cluster.new(URI.parse("redis://redis.ems1"))
  end

  def self.set_pool_size(pool_size)
    @@size = pool_size
  end

  def all_keys
    @client.keys
  end

  def keys(pattern)
    @client.keys(pattern)
  end

  def scan_each(pattern)
    keys = [] of String
    @client.scan_each(match: pattern) do |key|
       keys << key
    end

    keys
  end

  def hash_set(key : String, field, value)
    @client.hset(key, field.to_s, value.to_s)
  end

  def hash_get(key : String, field)
    "#{@client.hget(key, field.to_s)}"
  end

  def hash_del(key : String, field)
    return nil
  end

  def set(key : String, value)
    @client.set(key, value.to_s)
  end

  def get(key : String)
    @client.get(key)
  end

  def expire(key : String, duration)
    @client.expire(key, duration)
  end

  def get_job(job_id : String)
    job_hash = @client.hget("sched/id2job", job_id)
    if !job_hash
      raise "Get job (id = #{job_id}) from redis failed."
    end
    Job.new(JSON.parse(job_hash).as_h, job_id)
  end

  def update_wtmp(testbox : String, wtmp_hash : Hash)
    @client.hset("sched/tbox_wtmp", testbox, wtmp_hash.to_json)
  end

  def set_job(job : Job)
    hash_set("sched/id2job", job.id, job.to_json)
  end

  def remove_finished_job(job_id : String)
    @client.hdel("sched/id2job", job_id)
  end
end
