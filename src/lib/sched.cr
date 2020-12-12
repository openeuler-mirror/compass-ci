# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"
require "yaml"

require "./job"
require "./env"
require "./block_helper"
require "./taskqueue_api"
require "./remote_git_client"
require "../scheduler/constants"
require "../scheduler/jobfile_operate"
require "../scheduler/redis_client"
require "../scheduler/elasticsearch_client"

require "../scheduler/submit_job"
require "../scheduler/find_job_boot"
require "../scheduler/find_next_job_boot"
require "../scheduler/close_job"
require "../scheduler/request_cluster_state"
require "../scheduler/update_job_parameter"
require "../scheduler/create_job_cpio"
require "../scheduler/download_file"

class Sched
  property es
  property redis
  property block_helper

  def initialize(env : HTTP::Server::Context)
    @es = Elasticsearch::Client.new
    @redis = Redis::Client.new
    @task_queue = TaskQueueAPI.new
    @block_helper = BlockHelper.new
    @rgc = RemoteGitClient.new
    @env = env
    @log = env.log.as(JSONLogger)
  end

  def debug_message(response)
    @log.info(%({"from": "#{@env.request.remote_address}", "response": #{response.to_json}}))
  end

  def alive(version)
    debug_message("Env= {\n#{`export`}}")
    "LKP Alive! The time is #{Time.local}, version = #{version}"
  end

  def normalize_mac(mac : String)
    mac.gsub(":", "-")
  end

  def set_host_mac(mac : String, hostname : String)
    @redis.hash_set("sched/mac2host", normalize_mac(mac), hostname)
  end

  def del_host_mac(mac : String)
    @redis.hash_del("sched/mac2host", normalize_mac(mac))
  end

  def set_host2queues(hostname : String, queues : String)
    @redis.hash_set("sched/host2queues", hostname, queues)
  end

  def del_host2queues(hostname : String)
    @redis.hash_del("sched/host2queues", hostname)
  end

  def auto_submit_idle_job(tbox_group)
    full_path_patterns = "#{ENV["CCI_REPOS"]}/lab-#{ENV["lab"]}/allot/idle/#{tbox_group}/*.yaml"
    extra_job_fields = [
      "idle_job=true",
      "MASTER_FLUENTD_HOST=#{ENV["MASTER_FLUENTD_HOST"]}",
      "MASTER_FLUENTD_PORT=#{ENV["MASTER_FLUENTD_PORT"]}",
    ]

    Jobfile::Operate.auto_submit_job(
      full_path_patterns,
      "testbox: #{tbox_group}",
      extra_job_fields) if Dir.glob(full_path_patterns).size > 0
  end

  def update_tbox_wtmp
    testbox = ""
    hash = Hash(String, String).new

    time = Time.local.to_s("%Y-%m-%d %H:%M:%S")
    hash["time"] = time

    %w(mac ip job_id tbox_name tbox_state).each do |parameter|
      if (value = @env.params.query[parameter]?)
        case parameter
        when "tbox_name"
          testbox = value
        when "tbox_state"
          hash["state"] = value
        when "mac"
          hash["mac"] = normalize_mac(value)
        else
          hash[parameter] = value
        end
      end
    end

    @redis.update_wtmp(testbox, hash)

    # json log
    hash["testbox"] = testbox
    @log.info(hash.to_json)
  end

  def report_ssh_port
    testbox = @env.params.query["tbox_name"]
    ssh_port = @env.params.query["ssh_port"].to_s
    job_id = @env.params.query["job_id"].to_s

    if testbox && ssh_port
      @redis.hash_set("sched/tbox2ssh_port", testbox, ssh_port)
    end

    @log.info(%({"job_id": "#{job_id}", "state": "set ssh port", "ssh_port": "#{ssh_port}", "tbox_name": "#{testbox}"}))
  end

  private def query_consumable_keys(shortest_queue_name)
    keys = [] of String
    search = "sched/" + shortest_queue_name + "*"
    response = @task_queue.query_keys(search)

    return keys unless response[0] == 200

    key_list = JSON.parse(response[1].to_json).as_a

    # add consumable keys
    key_list.each do |key|
      queue_name = consumable_key?("#{key}")
      keys << queue_name if queue_name
    end

    return keys
  end

  private def consumable_key?(key_name)
    if key_name =~ /(.*)\/(.*)$/
      case $2
      when "in_process"
        return nil
      when "ready"
        return $1
      when "idle"
        return key_name
      else
        return key_name
      end
    end

    return nil
  end
end
