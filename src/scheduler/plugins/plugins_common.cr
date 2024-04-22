# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../redis_client"
require "../elasticsearch_client"
require "../../lib/utils"
require "../../lib/json_logger"
require "../../lib/etcd_client"
require "../../lib/remote_git_client"
require "../../lib/scheduler_api"

class PluginsCommon
  def initialize
    @etcd = EtcdClient.new
    @rgc = RemoteGitClient.new
    @es = Elasticsearch::Client.new
    @redis = Redis::Client.instance
    @log = JSONLogger.new
    @scheduler_api = SchedulerAPI.new
  end

  def update_current(key, current)
    puts "key: #{key}, current: #{current}"
    res = @etcd.range(key)
    return 0 if res.count == 0

    val = JSON.parse(res.kvs[0].value.not_nil!).as_h
    new_val = val.dup
    cur_val = new_val.has_key?("current") ? new_val["current"].as_h : Hash(String, JSON::Any).new
    return 1 if current == cur_val

    cur_val.any_merge!(current)
    new_val.any_merge!({"current" => cur_val})
    puts "key: #{key}, new current: #{current}"

    res = @etcd.update_base_version(key, new_val.to_json, res.kvs[0].version)
    ret = res ? 1 : -1
    return ret
  end

  def loop_update_current(key, current, loop_times = 50)
    loop_times.times do
      ret = update_current(key, current)
      return ret if ret >= 0
      sleep 1
    end

    return -1
  end

  # value = {"job.id" => "job_state"}}
  def update_waited(key, value)
    puts "key: #{key}, value: #{value}"
    res = @etcd.range(key)
    return 0 if res.count == 0

    val = JSON.parse(res.kvs[0].value.not_nil!).as_h
    puts "real: #{res.kvs[0].value.not_nil!}"
    new_val = val.dup
    cur_val = new_val.has_key?("waited") ? new_val["waited"].as_a : Array(JSON::Any).new
    cur_val << JSON.parse(value.to_json)

    new_val.any_merge!({"waited" => cur_val.uniq!})

    puts "new_val: #{new_val}"
    puts "version: #{res.kvs[0].version}"
    puts "key: #{key}"

    res = @etcd.update_base_version(key, new_val.to_json, res.kvs[0].version)
    ret = res ? 1 : -1
    return ret
  end

  def loop_update_waited(key, value, loop_times = 50)
    loop_times.times do
      ret = update_waited(key, value)
      return ret if ret >= 0
      sleep 1
    end

    return -1
  end

  def wait2ready(wait)
    ready = wait.gsub("sched/wait/", "sched/ready/")
    @etcd.move(wait, ready)
  end

  def wait2die(wait)
    die = wait.gsub("sched/wait/", "sched/die/")
    @etcd.move(wait, die)
    close_die_job(die)
  end

  def wait2ready(wait, value)
    ready = wait.gsub("sched/wait/", "sched/ready/")
    @etcd.move(wait, ready, value)
  end

  def wait2die(wait, value)
    die = wait.gsub("sched/wait/", "sched/die/")
    @etcd.move(wait, die, value)
    close_die_job(die)
  end

  def save_job2es(job)
    response = @es.set_job_content(job)
    msg = (response["error"]? ? response["error"]["root_cause"] : "")
    raise msg.to_s if response["error"]?
  end

  def save_job2etcd(job)
    @etcd.put("sched/id2job/#{job.id}", job.shrink_to_etcd_fields.to_json)
  end

  def close_die_job(die)
    spawn @scheduler_api.close_job(die.split("/")[-1], job_health: "failed", source: "scheduler")
  end
end
