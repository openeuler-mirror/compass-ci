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
  IS_CLUSTER = (ENV.has_key?("IS_CLUSTER") ? ENV["IS_CLUSTER"] : false)
  PASSWD = ENV["REDIS_PASSWORD"]
  @@size = 25

  def self.instance
    Singleton::Of(self).instance
  end

  def initialize(host = HOST, port = PORT, passwd = PASSWD)
    if IS_CLUSTER
      @client = Redis::Cluster.new(URI.parse("redis://#{host}:#{port}"))
    else
      @client = Redis::Client.new(URI.parse("redis://:#{URI.encode_www_form(passwd)}@#{host}:#{port}"))
    end
  end

  def self.set_pool_size(pool_size)
    @@size = pool_size
  end

  def keys(pattern)
    @client.keys(pattern)
  end

  def scan_each(pattern)
    keys = [] of String
    if IS_CLUSTER
      @client.scan_each(match: pattern) do |key|
        keys << key
      end
    else
      return @client.keys(pattern)
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

  def del(key : String)
    @client.del(key)
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

  def update_job(job_content : JSON::Any | Hash)
    job_id = job_content["id"].to_s

    job = get_job(job_id)
    job.update(job_content)

    hash_set("sched/id2job", job_id, job.dump_to_json)
  end

  def set_job(job : Job)
    hash_set("sched/id2job", job.id, job.to_json)
  end

  def remove_finished_job(job_id : String)
    @client.hdel("sched/id2job", job_id)
  end
end
