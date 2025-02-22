# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "redis"
require "redis/cluster"

require "./constants"
require "../job"
require "singleton"

class RedisClient
  class_property :client
  @@size = 25

  # In-memory hash to simulate Redis when has_redis is false
  @in_mem_hash : Hash(String, Hash(String, String)) = Hash(String, Hash(String, String)).new

  def self.instance
    Singleton::Of(self).instance
  end

  def initialize
    host = Sched.options.redis_host
    port = Sched.options.redis_port
    passwd = Sched.options.redis_passwd

    if Sched.options.has_redis
      if Sched.options.redis_is_cluster
        @client = Redis::Cluster.new(URI.parse("redis://:#{passwd}@#{host}:#{port}"))
      else
        @client = Redis::Client.new(URI.parse("redis://:#{URI.encode_www_form(passwd)}@#{host}:#{port}"))
      end
    else
      @client = nil # No Redis client when has_redis is false
    end
  end

  def self.set_pool_size(pool_size)
    @@size = pool_size
  end

  def client
    @client.not_nil!
  end

  def scan_each(pattern)
    if Sched.options.has_redis
      keys = [] of String
      if Sched.options.redis_is_cluster
        self.client.scan_each(match: pattern) do |key|
          keys << key
        end
      else
        return self.client.keys(pattern)
      end
      keys
    else
      # Simulate keys matching in in-memory hash
      prefix = pattern.chomp('*')
      @in_mem_hash.keys.select { |key| key.starts_with?(prefix) }
    end
  end

  def hash_set(key : String, field, value)
    if Sched.options.has_redis
      self.client.hset(key, field.to_s, value.to_s)
    else
      @in_mem_hash[key] ||= Hash(String, String).new
      @in_mem_hash[key][field.to_s] = value.to_s
    end
  end

  def hash_get(key : String, field)
    if Sched.options.has_redis
      self.client.hget(key, field.to_s).to_s
    else
      @in_mem_hash[key]?.try(&.[](field.to_s)) || ""
    end
  end

  def hash_del(key : String, field)
    if Sched.options.has_redis
      self.client.hdel(key, field.to_s)
    else
      @in_mem_hash[key]?.try(&.delete(field.to_s))
    end
  end

  def set(key : String, value)
    if Sched.options.has_redis
      self.client.set(key, value.to_s)
    else
      @in_mem_hash[key] = {"" => value.to_s}
    end
  end

  def get(key : String)
    if Sched.options.has_redis
      self.client.get(key)
    else
      @in_mem_hash[key]?.try(&.[](""))
    end
  end

  def del(key : String)
    if Sched.options.has_redis
      self.client.del(key)
    else
      @in_mem_hash.delete(key)
    end
  end

  def expire(key : String, duration)
    if Sched.options.has_redis
      self.client.expire(key, duration)
    else
      # Ignore expire for in-memory hash
    end
  end

  def get_job(job_id : String)
    if Sched.options.has_redis
      job_hash = self.client.hget("sched/id2job", job_id)
      if !job_hash
        raise "Get job (id = #{job_id}) from redis failed."
      end
      Job.new(JSON.parse(job_hash).as_h, job_id)
    else
      job_hash = @in_mem_hash["sched/id2job"]?.try(&.[](job_id))
      if !job_hash
        raise "Get job (id = #{job_id}) from in-memory hash failed."
      end
      Job.new(JSON.parse(job_hash).as_h, job_id)
    end
  end

  def update_wtmp(testbox : String, wtmp_hash : Hash)
    if Sched.options.has_redis
      self.client.hset("sched/tbox_wtmp", testbox, wtmp_hash.to_json)
    else
      @in_mem_hash["sched/tbox_wtmp"] ||= Hash(String, String).new
      @in_mem_hash["sched/tbox_wtmp"][testbox] = wtmp_hash.to_json
    end
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
    if Sched.options.has_redis
      self.client.hdel("sched/id2job", job_id)
    else
      @in_mem_hash["sched/id2job"]?.try(&.delete(job_id))
    end
  end
end
