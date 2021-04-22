# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "set"
require "kemal"
require "yaml"

require "./mq"
require "./scheduler_api"
require "../scheduler/elasticsearch_client"
require "../lifecycle/constants"

class String
  def bigger_than?(time)
    return false if self.empty?

    time = time.to_s
    return true if time.empty?

    # Historical data contains time in the format of "%Y-%m-%d %H:%M:%S"
    # Compatibility processing is required
    time = time.gsub(/ /, "T")
    time = Time.parse(time, "%Y-%m-%dT%H:%M:%S", Time.local.location)
    self_time = Time.parse(self, "%Y-%m-%dT%H:%M:%S", Time.local.location)

    self_time > time
  end
end

class Lifecycle
  property es

  def initialize
    @mq = MQClient.instance
    @es = Elasticsearch::Client.new
    @scheduler_api = SchedulerAPI.new
    @log = JSONLogger.new
    @jobs = Hash(String, JSON::Any).new
    @machines = Hash(String, JSON::Any).new
    @match = Hash(String, Set(String)).new {|h, k| h[k] = Set(String).new}
  end

  def alive(version)
    "Lifecycle Alive! The time is #{Time.local}, version = #{version}"
  rescue e
    @log.warn({
      "resource" => "/alive",
      "message" => e.inspect_with_backtrace
    }.to_json)
  end

  def init_from_es
    jobs = get_active_jobs
    jobs.each do |result|
      job_id = result["_id"].to_s
      job = result["_source"].as_h
      job.delete_if{|key, _| !JOB_KEYWORDS.includes?(key)}

      @jobs[job_id] = JSON.parse(job.to_json)
      @match[job["testbox"].to_s] << job_id
    end

    machines = get_active_machines
    machines.each do |result|
      testbox = result["_id"].to_s
      machine = result["_source"].as_h
      machine.delete("history")

      machine = JSON.parse(machine.to_json)
      @machines[testbox] = machine

      deal_match_job(testbox, machine["job_id"].to_s)
    end
  rescue e
    @log.warn({
      "resource" => "init_from_es",
      "message" => e.inspect_with_backtrace
    }.to_json)
  end

  def deal_match_job(testbox, job_id)
    @match[testbox].each do |id|
      next if id == job_id

      msg = {
        "job_id" => id,
        "job_state" => "abnormal",
        "testbox" => testbox
      }
      @mq.publish_confirm("job_mq", msg.to_json)
      @match[testbox].delete(id)
    end
  end

  def get_active_jobs
    query = {
      "size" => 10000,
      "query" => {
        "term" => {
          "job_state" => "boot"
        }
      }
    }
    @es.search("jobs", query)
  end

  def get_active_machines
    query = {
      "size" => 10000,
      "query" => {
        "terms" => {
          "state" => ["booting", "running", "rebooting"]
        }
      }
    }
    @es.search("testbox", query)
  end

  def mq_event_loop
    puts "deal job events"
    event = JSON::Any.new(nil)
    begin
      q = @mq.ch.queue("job_mq", durable: false)
      q.subscribe(no_ack: false) do |msg|
        event = JSON.parse(msg.body_io.to_s)
        job_state = event["job_state"]?

        case job_state
        when "boot"
          on_job_boot(event)
        when "close"
          on_job_close(event)
        when "abnormal"
          on_abnormal_job(event)
        when "crash"
          on_job_crash(event)
        else
          on_other_job(event)
        end
        @mq.ch.basic_ack(msg.delivery_tag)
      end
    rescue e
      @log.warn({
        "resource" => "mq_event_loop",
        "message" => e.inspect_with_backtrace,
        "event" => event
      }.to_json)
    end
  end

  def on_other_job(event)
    event_job_id = event["job_id"].to_s
    return if event_job_id.empty?

    update_cached_job(event_job_id, event)

    job = @jobs[event_job_id]?
    return unless job

    testbox = job["testbox"].to_s
    update_cached_machine(testbox, event)
  end

  def update_cached_machine(testbox, event)
    machine = @machines[testbox]?
    if machine
      return unless event["time"].to_s.bigger_than?(machine["time"]?)

      machine.as_h["time"] = event["time"]
    else
      machine = @es.get_tbox(testbox)
      return unless machine

      machine.as_h.delete("history")
      @machines[testbox] = machine
    end
  end

  def update_cached_job(job_id, event)
    job = @jobs[job_id]?
    if job
      @jobs[job_id] = JSON.parse(job.as_h.merge!(event.as_h).to_json)
    else
      job = @es.get_job(job_id)
      return unless job
      return if JOB_CLOSE_STATE.includes?(job["job_state"]?)

      job = job.dump_to_json_any.as_h
      job.delete_if{|key, _| !JOB_KEYWORDS.includes?(key)}
      job["job_state"] = event["job_state"]
      @jobs[job_id] = JSON.parse(job.to_json)
    end
  end

  def on_abnormal_job(event)
    event_job_id = event["job_id"].to_s
    return unless @jobs.has_key?(event_job_id)

    close_job(event_job_id, "abnormal")
  end

  def on_job_close(event)
    event_job_id = event["job_id"].to_s
    job = @jobs[event_job_id]?
    return unless job

    @jobs.delete(event_job_id)
    update_cached_machine(job["testbox"].to_s, event)
  end

  def on_job_crash(event)
    event_job_id = event["job_id"].to_s
    if @jobs[event_job_id]?
      close_job(event_job_id, "crash")
    end

    testbox = event["testbox"].to_s
    reboot_crash_machine(testbox, event)
  end

  def on_job_boot(event)
    event_job_id = event["job_id"]?.to_s
    @jobs[event_job_id] = event unless event_job_id.empty?
    machine_info = @machines[event["testbox"]]?
    deal_boot_machine(machine_info, event)
  end

  def deal_boot_machine(machine_info, event)
    event_job_id = event["job_id"]?.to_s

    unless machine_info
      @machines[event["testbox"].to_s] = event
      return
    end

    machine_job_id = machine_info["job_id"].to_s
    # The job is not updated
    # No action is required
    return if event_job_id == machine_job_id

    time = machine_info["time"]?
    # Skip obsolete event
    return unless event["time"].to_s.bigger_than?(time)

    @machines[event["testbox"].to_s] = event

    deal_match_job(event["testbox"].to_s, event_job_id)

    # No previous job to process
    return if machine_job_id.empty?
    return unless @jobs.has_key?(machine_job_id)

    close_job(machine_job_id, "abnormal")
  end

  def max_time(times)
    result = ""
    times.each do |time|
      result = time if time.to_s.bigger_than?(result)
    end
    return result
  end

  def timeout_job_loop
    dead_job_id = nil
    loop do
      close_job(dead_job_id, "timeout") if dead_job_id
      deadline, dead_job_id = get_min_deadline
      # deal timeout job
      next if dead_job_id && deadline <= Time.local

      sleep_until(deadline)
    rescue e
      @log.warn({
        "resource" => "timeout_job_loop",
        "message" => e.inspect_with_backtrace,
        "job_id" => dead_job_id
      }.to_json)
    end
  end

  def timeout_machine_loop
    dead_machine_name = nil
    loop do
      reboot_timeout_machine(dead_machine_name) if dead_machine_name
      deadline, dead_machine_name = get_min_deadline_machine
      next if dead_machine_name && deadline <= Time.local

      sleep_until(deadline)
    rescue e
      @log.warn({
        "resource" => "timeout_machine_loop",
        "message" => e.inspect_with_backtrace,
        "testbox" => dead_machine_name
      }.to_json)
    end
  end

  def sleep_until(deadline)
    s = (deadline - Time.local).total_seconds
    sleep(s)
  end

  def get_min_deadline
    deadline = (Time.local + 60.second)
    dead_job_id = nil
    @jobs.each do |id, job|
      next unless job["deadline"]?
      job_deadline = Time.parse(job["deadline"].to_s, "%Y-%m-%dT%H:%M:%S", Time.local.location)
      return job_deadline, id if Time.local >= job_deadline
      next unless deadline > job_deadline

      deadline = job_deadline
      dead_job_id = id
    end
    return deadline, dead_job_id
  end

  def get_min_deadline_machine
    deadline = (Time.local + 60.second)
    dead_machine_name = nil
    @machines.each do |name, machine|
      next if machine["deadline"]?.to_s.empty?

      machine_deadline = Time.parse(machine["deadline"].to_s, "%Y-%m-%dT%H:%M:%S", Time.local.location)
      return machine_deadline, name if Time.local >= machine_deadline
      next unless deadline > machine_deadline

      deadline = machine_deadline
      dead_machine_name = name
    end
    return deadline, dead_machine_name
  end

  def close_job(job_id, reason)
    @jobs.delete(job_id)
    spawn @scheduler_api.close_job(job_id, reason, "lifecycle")
    @log.info({
      "job_id" => job_id,
      "state" => "close",
      "reason" => reason,
      "type" => "job"
    }.to_json)
  end

  def reboot_crash_machine(testbox, event)
    @machines.delete(testbox)
    machine = @es.get_tbox(testbox)
    return unless machine
    return unless event["time"].to_s.bigger_than?(machine["time"]?)

    reboot_machine(testbox, machine, "crash")
  end

  def reboot_timeout_machine(testbox)
    @machines.delete(testbox)
    machine = @es.get_tbox(testbox)
    return unless machine
    return if MACHINE_CLOSE_STATE.includes?(machine["state"])

    deadline = machine["deadline"]?
    return unless deadline

    deadline = Time.parse(deadline.to_s, "%Y-%m-%dT%H:%M:%S", Time.local.location)
    return if Time.local < deadline

    reboot_machine(testbox, machine, "timeout")
  end

  def reboot_machine(testbox, machine, reason)
    mq_queue = get_machine_reboot_queue(testbox)
    machine.as_h.delete("history")
    machine.as_h["testbox"] = JSON::Any.new(testbox)
    @mq.publish_confirm(mq_queue, machine.to_json, durable: true)

    machine["state"] = "rebooting_queue"
    machine["time"] = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
    @es.update_tbox(testbox, machine.as_h)
    @log.info({
      "type" => "testbox",
      "reason" => reason,
      "testbox" => testbox,
      "state" => "reboot"
    }.to_json)
  end

  def get_machine_reboot_queue(testbox)
    if testbox.includes?(".")
      testbox =~ /(.*)-\d+$/
    else
      testbox =~ /(.*)--.*/
    end
    $1
  rescue
    testbox
  end
end
