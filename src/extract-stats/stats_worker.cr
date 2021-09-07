# SPDX-License-Identifier: GPL-2.0-only
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "../lib/etcd_client"
require "../lib/json_logger"
require "../scheduler/elasticsearch_client"
require "../scheduler/redis_client"
require "../scheduler/constants"
require "./regression_client"
require "./constants.cr"

class StatsWorker
  @@metric_failure = File.read("#{ENV["LKP_SRC"]}/etc/failure").strip.split("\n").as(Array(String))
  @@__is_failure_cache = Hash(String, Bool).new

  def initialize
    @es = Elasticsearch::Client.new
    @etcd = EtcdClient.new
    @rc = RegressionClient.new
    @log = JSONLogger.new
  end

  def handle(queue_path, channel, commit_channel)
    begin
      res = @etcd.range(queue_path)
      return nil if res.count == 0

      job_id = queue_path.split("/")[-1]
      job = @es.get_job_content(job_id)
      result_root = job["result_root"]?
      result_post_processing(job_id, result_root.to_s, queue_path)
      commit_channel.send(job["upstream_commit"].to_s) if job["nr_run"]? && job["upstream_commit"]? && job["base_commit"]?
      @etcd.delete(queue_path)
    rescue e
      channel.send(queue_path)
      @log.error(e.message)
      # incase of many error message when ETCD, ES does not work
      sleep(10)
    ensure
      delete_id2job(job_id) if job_id
      @etcd.close
    end
  end

  def delete_id2job(id)
    res = @etcd.delete("sched/id2job/#{id}")
    @log.info("extract-stats delete id2job from etcd #{id}: #{res}")
  end

  def boards_store(result_root : String)
    file_path = "#{result_root}/boards-scan"
    return unless File.exists?(file_path)

    file_info = File.open(file_path)
    boards_info = JSON.parse(file_info)

    @es.@client.index(
      {
        :index => "machines",
        :type => "_doc",
        :refresh => "wait_for",
        :id => boards_info["id"],
        :body => boards_info,
      }
    )
  end

  def result_post_processing(job_id : String, result_root : String, queue_path : String)
    return nil unless result_root && File.exists?(result_root)

    suite = result_root.split("/")[2]
    boards_store(result_root) if suite == "boards-scan"
    # extract stats.json
    system "#{ENV["CCI_SRC"]}/sbin/result2stats #{result_root}"
    # storage stats to job in es
    store_stats_es(result_root, job_id, queue_path)
  end

  def is_failure(stats_field)
    if @@__is_failure_cache.has_key?(stats_field)
      @@__is_failure_cache[stats_field]
    else
      @@__is_failure_cache[stats_field] = __is_failure(stats_field)
    end
  end

  def __is_failure(stats_field)
    return false if stats_field.index(".time.")
    return false if stats_field.index(".timestamp.")
    return true if @@metric_failure.any? { |pattern| stats_field =~ %r{^#{pattern}} }
    false
  end

  def store_stats_es(result_root : String, job_id : String, queue_path : String)
    stats_path = "#{result_root}/stats.json"
    return unless File.exists?(stats_path)

    stats = File.open(stats_path) do |file|
      JSON.parse(file)
    end

    errid = Array(String).new
    stats.as_h.keys.each do |k|
      errid << k.to_s if is_failure(k.to_s)
    end

    update_content = Hash(String, Array(String) | Hash(String, JSON::Any)).new
    update_content.merge!({"stats" => stats.as_h, "errid" => errid})

    error_ids = get_error_ids_by_json(result_root)
    update_content.merge!({"error_ids" => error_ids}) unless error_ids.empty?

    @es.@client.update(
      {
        :index => "jobs", :type => "_doc",
        :refresh => "wait_for",
        :id => job_id,
        :body => {:doc => update_content},
      }
    )

    new_error_ids = check_new_error_ids(error_ids, job_id)
    unless new_error_ids.empty?
      sample_error_id = new_error_ids.sample
      @log.info("send a delimiter task: job_id is #{job_id}")
      queue = "#{DELIMITER_TASK_QUEUE}/#{job_id}"
      value = %({"job_id": "#{job_id}", "error_id": "#{sample_error_id}"})
      @etcd.put(queue, value)

      msg = %({"job_id": "#{job_id}", "new_error_id": "#{sample_error_id}"})
      @log.info(msg)
    end
    msg = %({"job_id": "#{job_id}", "job_state": "extract_finished"})
    @log.info(msg)
  end

  def check_new_error_ids(error_ids : Array, job_id : String)
    new_error_ids = [] of String
    error_ids.each do |error_id|
      begin
        is_exists = @rc.check_error_id error_id
      rescue e
        @log.error(e.message)
        next
      end
      next if is_exists

      new_error_ids << error_id
      @rc.store_error_info error_id, job_id
    end
    new_error_ids
  end

  def get_error_ids_by_json(result_root : String)
    error_ids = [] of String
    ERROR_ID_FILES.each do |filename|
      filepath = File.join(result_root, filename)
      next unless File.exists?(filepath)

      content = File.open(filepath) do |file|
        JSON.parse(file)
      end
      error_ids.concat(content.as_h.keys)
    end

    error_ids.each do |error_id|
      error_ids.delete(error_id) if error_id.ends_with?(".message")
    end

    return error_ids
  end
end
