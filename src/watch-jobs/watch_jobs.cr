# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../scheduler/plugins/plugins_common"
require "./constants"

# case1: handle the prefix /queues/sched/wait/ jobs when start the service
# case2: watch id2job queue
#   case1: handle wait job if id2job has wait field
#   case2: handle waited job if id2job has waited field
class WatchJobs < PluginsCommon
  def handle_jobs
    revision = handle_wait_list
    watch_id2jobs(revision)
  end

  def handle_wait_list
    wait_list, revision = get_wait_list
    wait_list.each do |wait|
      handle_wait(wait)
    end

    return revision
  end

  def get_wait_list
    prefix = "sched/wait/"
    response = @etcd.range_prefix(prefix)
    wait_list = response.kvs
    revision = response.header.not_nil!.revision

    return wait_list, revision
  end

  # {"desired" => {"crystal.2454672" => {"job_health" => "success"}, "crystal.2454674" => {"job_health" => "success"}}}
  # {"current" => {"crystal.2454672" => {"job_health" => "failed"}, "crystal.2454674" => {"job_health" => "failed"}}}
  def handle_wait(wait)
      key = wait.key
      val = JSON.parse(wait.value.not_nil!).as_h
      return unless val.has_key?("desired")

      desired = val["desired"].as_h
      current = val.has_key?("current") ? val["current"].as_h : Hash(String, JSON::Any).new
      return wait2ready(key, val) if desired == current

      ret = wait2die_by_current(key, val, current)
      return if ret != nil

      es_current = current_from_es(desired)
      current.any_merge!(es_current)
      val.any_merge!({"current" => current})
      return wait2ready(key, val) if desired == current

      wait2die_by_current(key, val, current)
  end

  def wait2die_by_current(key, val, current)
      current.each do |k, v|
        f_k = v.as_h.first_key
        f_v = v.as_h.first_value.to_s
        return wait2die(key, val) if WATCH_STATE[f_k]["bad"].includes?(f_v)
        return wait2die(key, val) unless WATCH_STATE[f_k]["good"].includes?(f_v)
      end
  end

  def current_from_es(desired)
    current = Hash(String, JSON::Any).new
    desired.each do |k, v|
      field = find_job_field(k, v.as_h.first_key)
      next unless field

      current[k] = JSON.parse({v.as_h.first_key => field}.to_json)
    end

    return current
  end

  def find_job_field(id, item)
    job = @es.get_job(id).not_nil!

    return job[item]?
  end

  def watch_id2jobs(revision)
    channel = Channel(Array(Etcd::Model::WatchEvent)).new
    ec = EtcdClient.new
    watcher = ec.watch_prefix("sched/id2job", start_revision: revision.to_i64, filters: [Etcd::Watch::Filter::NODELETE]) do |events|
      channel.send(events)
    end

    spawn { watcher.start }

    loop_handle(channel)
  end

  def loop_handle(channel)
    while true
      begin
        events = channel.receive
        events.each do |event|
          handle_event(event)
        end
      rescue e
        @log.error(e)
        sleep 1
      end
    end
  end

  # event key: /queues/sched/id2job/crystal.2529835
  # evnet val: job content
  def handle_event(event)
    key = event.kv.key
    val = event.kv.value
    @log.info("event key: #{key}")
    job = Job.new(JSON.parse(val.not_nil!), key.split("/")[-1])

    #on_waited(job) if job.has_key?("wait_by")
    on_waited(job) if job.has_key?("waited")
    on_wait(job) if job.has_key?("wait")
  end

  def on_wait(job)
    # {"desired": {"crystal.1" : {"job_health": "success"}, "crystal.2": {"job_health": "success"}}}
    # means job is waiting for: crystal.1 and crystal.2 to become desired k:v
    key = "sched/wait/#{job["queue"]}/#{job["subqueue"]}/#{job.id}"
    @log.info("wait key #{key}")
    res = @etcd.range(key)
    return if res.count == 0

    handle_wait(res.kvs[0])
  end

  # {"waited": [{"crystal.1" : "job_health"}, {"crystal.2" : "xxx"}]
  # which job : wait for my which field  = which value
  def on_waited(job)
    waited = job["waited"]?.not_nil!.as_a
    @log.info("waited arrary: #{waited}")
    waited.each do |item|
      k = item.as_h.first_key
      v = item.as_h.first_value
      res = @etcd.range("sched/id2job/#{k}")
      next if res.count == 0

      k_j = Job.new(JSON.parse(res.kvs[0].value.not_nil!), "#{k}")
      key = "sched/wait/#{k_j["queue"]}/#{k_j["subqueue"]}/#{k}"
      next unless job.has_key?(v.to_s)

      # {"current": {"crystal.1" : {"job_health": "success"}, "crystal.2": {"job_health": "success"}}}
      current = {job.id => {v.to_s => JSON::Any.new(job[v.to_s])}}
      loop_update_current(key, current)
      move_wait2other(key)
    end
  end

  def move_wait2other(key)
    res = @etcd.range(key)
    return if res.count == 0

    val = JSON.parse(res.kvs[0].value.not_nil!).as_h
    return unless val.has_key?("desired")
    return unless val.has_key?("current")

    desired = val["desired"].as_h
    current = val["current"].as_h
    return wait2ready(key, val) if desired == current

    wait2die_by_current(key, val, current)
  end
end
