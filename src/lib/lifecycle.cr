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
    @jobs = Hash(String, JobHash).new
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

      @jobs[job_id] = JobHash.new(job)
      @match[job["testbox"].to_s] << job_id
    end

    machines = get_active_machines
    machines.each do |result|
      testbox = result["_id"].to_s
      machine = result["_source"].as_h

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

  def init_from_es_loop
    loop do
      init_from_es
      @log.info("init from es loop")
      sleep 300
    end
  end

  def deal_match_job(testbox, job_id)
    @match[testbox].each do |id|
      next if id == job_id

      msg = {
        "job_id" => id,
        "job_health" => "abnormal",
        "job_stage" => "unknow",
        "testbox" => testbox
      }
      spawn @mq.retry_publish_confirm("job_mq", msg.to_json)
      @match[testbox].delete(id)
    end
  end

  def get_active_jobs
    query = {
      "size" => 10000,
      "_source" => JOB_KEYWORDS,
      "query" => {
        "bool" => {
          "must_not" => [
            {
              "terms" => {
                "job_stage" => ["submit", "finish"]
              }
            }
          ],
          "must" => [
            {
              "exists" => {
                "field" => "job_stage"
              }
            }
          ]
        }
      }
    }
    @es.search("jobs", query)
  end

  def get_active_machines
    query = {
      "size" => 10000,
      "_source" => TESTBOX_KEYWORDS,
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
        # cached messages are cailbrated from the ES every 5 minutes
        # the non-unknow messages received five minutes age are outdated
        # no need to be processed
        if out_of_date?(event)
          @mq.ch.basic_ack(msg.delivery_tag)
          next
        end

        case event["job_stage"]?
        when "boot"
          on_job_boot(event)
        when "finish"
          on_job_finish(event)
        when "unknow"
          on_unknow_job(event)
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

  def out_of_date?(event)
    return false if event["job_stage"]? == "unknow"

    time = Time.parse(event["time"].to_s, "%Y-%m-%dT%H:%M:%S", Time.local.location)
    s = (Time.local - time).total_seconds

    return true if s >= 300
    return false
  end

  def on_unknow_job(event)
    job_health = event["job_health"]?
    case job_health
    when "crash"
      on_job_crash(event)
    when "abnormal"
      on_abnormal_job(event)
    else
      return
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

      @machines[testbox]  = JSON.parse(machine.as_h.merge!(event.as_h).to_json)
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
      job.import2hash(event.as_h)
    else
      job = @es.get_job(job_id)
      return unless job
      return if job["job_stage"]? == "finish"

      @jobs[job_id] = JobHash.new(job.shrink_to_etcd_fields)
    end
  end

  def on_abnormal_job(event)
    event_job_id = event["job_id"].to_s
    job = @jobs[event_job_id]?
    return unless job
    return if ["submit", "finish"].includes?(job["job_stage"])

    close_job(event_job_id, "abnormal")
  end

  def on_job_finish(event)
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
    @jobs[event_job_id] = JobHash.new(event.as_h) unless event_job_id.empty?
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
      dead_job_id = get_timeout_job
      if dead_job_id
        close_timeout_job(dead_job_id)
        next
      end

      sleep 30
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
      dead_machine_name = get_timeout_machine
      if dead_machine_name
        reboot_timeout_machine(dead_machine_name)
        next
      end

      sleep 30
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

  def get_timeout_job
    @jobs.each do |id, job|
      next unless job["deadline"]?
      next if job["job_stage"]? == "finish"

      job_deadline = Time.parse(job["deadline"].to_s, "%Y-%m-%dT%H:%M:%S", Time.local.location)
      return id if Time.local >= job_deadline
    end
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

  def get_timeout_machine
    @machines.each do |name, machine|
      next if machine["deadline"]?.to_s.empty?
      next if machine["state"]?.to_s == "rebooting_queue"

      machine_deadline = Time.parse(machine["deadline"].to_s, "%Y-%m-%dT%H:%M:%S", Time.local.location)
      return name if Time.local >= machine_deadline
    end
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

  def close_job(job_id, job_health)
    @jobs.delete(job_id)
    spawn @scheduler_api.close_job(job_id, job_health: job_health, source: "lifecycle")
    @log.info({
      "job_id" => job_id,
      "state" => "close",
      "job_health" => job_health,
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

  def close_timeout_job(job_id)
    @jobs.delete(job_id)
    job = @es.get_job(job_id)
    return unless job
    return if ["submit", "finish"].includes?(job["job_stage"]?)

    deadline = job["deadline"]?.to_s
    return if deadline.empty?

    deadline = Time.parse(deadline.to_s, "%Y-%m-%dT%H:%M:%S", Time.local.location)
    if Time.local < deadline
      @jobs[job_id] = JobHash.new(job.shrink_to_etcd_fields)
    else
      reboot_timeout_machine(job["testbox"])
      close_job(job_id, "timeout")
    end
  end

  def reboot_timeout_machine(testbox)
    @machines.delete(testbox)
    machine = @es.get_tbox(testbox)
    return unless machine
    return unless machine["state"]?
    return if MACHINE_CLOSE_STATE.includes?(machine["state"])

    deadline = machine["deadline"]?.to_s
    return if deadline.empty?

    deadline = Time.parse(deadline.to_s, "%Y-%m-%dT%H:%M:%S", Time.local.location)
    if Time.local < deadline
      @machines[testbox] = machine
    else
      reboot_machine(testbox, machine, "timeout")
    end
  end

  def reboot_machine(testbox, machine, reason)
    mq_queue = get_machine_reboot_queue(testbox)
    machine.as_h.delete("history")
    machine.as_h["testbox"] = JSON::Any.new(testbox)
    spawn @mq.retry_publish_confirm(mq_queue, machine.to_json, durable: true)

    machine["state"] = "rebooting_queue"
    machine["time"] = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
    @es.update_tbox(testbox, machine.as_h)
    @log.info({
      "type" => "testbox",
      "reason" => reason,
      "testbox" => testbox,
      "state" => "reboot",
      "mq_queue" => mq_queue,
    }.to_json)
  end

  # dc and vm are deployed on different physical machines.
  # The restart service is a thread of each multi-qemu or multi-docker on each physical machine.
  # Therefore, the restart queue must be specific to the thread of the physical machine.
  # However, physical machines are restarted on the IBMC service.
  # The restart queue should be set to one.
  def get_machine_reboot_queue(testbox)
    return "reboot_physical_machine" unless testbox.includes?(".")

    testbox =~ /(.*)-\d+$/
    $1
  rescue
    testbox
  end
end
