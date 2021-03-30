# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../lib/etcd_client"
require "../scheduler/elasticsearch_client"
require "../scheduler/redis_client"
require "../scheduler/constants"
require "./regression_client"
require "./constants.cr"

class StatsWorker
  def initialize
    @es = Elasticsearch::Client.new
    @etcd = EtcdClient.new
    @rc = RegressionClient.new
  end

  def handle(queue_path, channel)
    begin
      res = @etcd.range(queue_path)
      return nil if res.count == 0

      job_id = queue_path.split("/")[-1]
      job = @es.get_job_content(job_id)
      result_root = job["result_root"]?
      result_post_processing(job_id, result_root.to_s, queue_path)
      @etcd.delete(queue_path)
    rescue e
      channel.send(queue_path)
      STDERR.puts e.message
      # incase of many error message when task-queue, ES does not work
      sleep(10)
    end
  end

  def result_post_processing(job_id : String, result_root : String, queue_path : String)
    return nil unless result_root && File.exists?(result_root)

    # extract stats.json
    system "#{ENV["CCI_SRC"]}/sbin/result2stats #{result_root}"
    # storage stats to job in es
    store_stats_es(result_root, job_id, queue_path)
    # send mail to submitter for job results
    system "#{ENV["CCI_SRC"]}/sbin/mail-job #{job_id}"
  end

  def store_stats_es(result_root : String, job_id : String, queue_path : String)
    stats_path = "#{result_root}/stats.json"
    return unless File.exists?(stats_path)

    stats = File.open(stats_path) do |file|
      JSON.parse(file)
    end

    update_content = Hash(String, Array(String) | Hash(String, JSON::Any)).new
    update_content.merge!({"stats" => stats.as_h})

    error_ids = get_error_ids_by_json(result_root)
    update_content.merge!({"error_ids" => error_ids}) unless error_ids.empty?

    @es.@client.update(
      {
        :index => "jobs", :type => "_doc",
        :id => job_id,
        :body => {:doc => update_content},
      }
    )

    new_error_ids = check_new_error_ids(error_ids, job_id)
    unless new_error_ids.empty?
      sample_error_id = new_error_ids.sample
      STDOUT.puts "send a delimiter task: job_id is #{job_id}"
      queue = "#{DELIMITER_TASK_QUEUE}/#{job_id}"
      value = {"error_id" => sample_error_id}
      @etcd.put(queue, value)

      msg = %({"job_id": "#{job_id}", "new_error_id": "#{sample_error_id}"})
      system "echo '#{msg}'"
    end
    msg = %({"job_id": "#{job_id}", "job_state": "extract_finished"})
    system "echo '#{msg}'"
  end

  def check_new_error_ids(error_ids : Array, job_id : String)
    new_error_ids = [] of String
    error_ids.each do |error_id|
      begin
        is_exists = @rc.check_error_id error_id
      rescue e
        STDERR.puts e.message
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
    error_ids
  end
end
