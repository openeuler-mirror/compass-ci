# SPDX-License-Identifier: GPL-2.0-only
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "yaml"

require "../lib/json_logger"
require "../elasticsearch_client"
require "../lib/redis_client"
require "../constants"
require "./regression_client"
require "./constants.cr"

class StatsWorker
  @@metric_failure = File.read("#{ENV["LKP_SRC"]}/etc/failure").strip.split("\n").as(Array(String))
  @@__is_failure_cache = Hash(String, Bool).new

  def initialize
    @es = Elasticsearch::Client.new
    @rc = RegressionClient.new
    @log = JSONLogger.new
  end

  def handle(job)
    begin
      result_post_processing(job)
    rescue e
      @log.error(e)
      # incase of many error message when ETCD, ES does not work
      sleep(10.seconds)
    end
  end

  def store_device(result_root, job)
    job_id = job.id?
    testbox = job.testbox?
    file_path = "#{result_root}/boards-scan"
    return unless File.exists?(file_path)
    is_store = job.is_store?
    return if is_store != "yes"

    lab_envir = job.lab?
    suite = job.suite?
    crystal_ip = job.crystal_ip?
    if crystal_ip
      cmd = "$LKP_SRC/sbin/hardware-gmail.sh #{file_path} #{lab_envir} \
      #{testbox} #{suite} #{crystal_ip}"
    else
      cmd = "$LKP_SRC/sbin/hardware-gmail.sh #{file_path} #{lab_envir} \
      #{testbox} #{suite}"
    end
    `#{cmd}`

    content = File.open(file_path) do |f|
      YAML.parse(f)
    end

    host_content = get_host_content(testbox)
    if host_content
      host_content_hash = host_content.as_h
      host_content_hash["device"] = JSON.parse(content.to_json)
      board_info = JSON.parse(host_content_hash.to_json)
    else
      board_info = JSON.parse({"device" => content}.to_json)
    end

    @es.@client.index(
      {
        :index => "hosts",
        :type => "_doc",
        :id => testbox,
        :body => board_info,
      }
    )
  rescue e
    msg = %({"job_id": "#{job_id}", "store_device error": "#{e}"})
    @log.warn({
      "message" => "job_id #{job_id}, store device error #{e}",
      "error_message" => e.inspect_with_backtrace.to_s
    })
  end

  def store_host_info(result_root : String, job)
    job_id = job.id?
    is_store = job.is_store?
    return if is_store != "yes"

    testbox = job.testbox?
    file_path = "#{result_root}/host-info"
    return unless File.exists?(file_path)

    lab_envir = job.lab?
    suite = job.suite?
    crystal_ip = job.crystal_ip?
    if crystal_ip
      cmd = "$LKP_SRC/sbin/hardware-gmail.sh #{file_path} #{lab_envir} \
      #{testbox} #{suite} #{crystal_ip}"
    else
      cmd = "$LKP_SRC/sbin/hardware-gmail.sh #{file_path} #{lab_envir} \
      #{testbox} #{suite}"
    end
    `#{cmd}`

    content = File.open(file_path) do |f|
      YAML.parse(f)
    end

    host_content = get_host_content(testbox)
    if host_content
      host_content_hash = host_content.as_h
      device = host_content_hash["device"]?
      if device
        content = JSON.parse(content.to_json).as_h
        content.any_merge!({"device" => device})
      end
    end

    host_info = JSON.parse(content.to_json)
    @es.@client.index(
      {
        :index => "hosts",
        :type => "_doc",
        :id => testbox,
        :body => host_info,
      }
    )
  rescue e
    msg = %({"job_id": "#{job_id}", "store_host_info error": "#{e}"})
    @log.warn({
      "message" => "job_id #{job_id}, store host info error #{e}",
      "error_message" => e.inspect_with_backtrace.to_s
    })
  end

  def get_host_content(testbox)
    query = {:index => "hosts", :type => "_doc", :id => testbox}
    if @es.@client.exists(query)
      result = @es.@client.get_source(query)
      return nil unless result.is_a?(JSON::Any)

      return result
    end
  end

  def result_post_processing(job)
    result_root = job.result_root
    result_root = "#{BASE_DIR}/#{result_root}"
    raise "result_root #{result_root} not exist" unless File.exists?(result_root)

    suite = job.suite?
    store_device(result_root, job) if suite == "boards-scan"
    store_host_info(result_root, job) if suite == "host-info"

    # extract stats.json
    system "#{ENV["CCI_SRC"]}/sbin/result2stats #{result_root}"

    # storage stats to job in es
    result_json = load_json_hash("#{result_root}/result.json")
    job.import2hash result_json.as_h if result_json

    stats_json = load_json_hash("#{result_root}/stats.json")
    job.import2hash ({"stats" => stats_json}) if stats_json
    add_errid(job)

    error_ids = load_error_ids(result_root)
    job.error_ids = error_ids unless error_ids.empty?

    notify_error(error_ids, job.id)
  end

  def load_json_hash(path : String)
    return nil unless File.exists?(path)

    JSON.parse(File.read(path))
  end

  def is_failure(stats_field : String)
    if @@__is_failure_cache.has_key?(stats_field)
      @@__is_failure_cache[stats_field]
    else
      @@__is_failure_cache[stats_field] = __is_failure(stats_field)
    end
  end

  def __is_failure(stats_field : String)
    return false if stats_field.index(".time.")
    return false if stats_field.index(".timestamp.")
    return true if @@metric_failure.any? { |pattern| stats_field =~ %r{^#{pattern}} }
    false
  end

  def add_errid(update_job : JobHash)
    return unless s = update_job.stats?

    e = Array(String).new
    s.as_h.keys.each { |k| e << k if is_failure(k) }
    update_job.errid = e
  end

  def notify_error(error_ids, job_id)
    new_error_ids = check_new_error_ids(error_ids, job_id)
    unless new_error_ids.empty?
      sample_error_id = new_error_ids.sample
      @log.info {"send a delimiter task: job_id is #{job_id}"}
      msg = {"job_id" => "#{job_id}", "new_error_id" => "#{sample_error_id}"}
      @log.info(msg)
    end
  end

  def check_new_error_ids(error_ids : Array, job_id : String)
    new_error_ids = [] of String
    error_ids.each do |error_id|
      begin
        is_exists = @rc.check_error_id error_id
      rescue e
        @log.error(e)
        next
      end
      next if is_exists

      new_error_ids << error_id
      @rc.store_error_info error_id, job_id
    end
    new_error_ids
  end

  def load_error_ids(result_root : String)
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
