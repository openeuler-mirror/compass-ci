# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"
require "yaml"

require "./mq"
require "./job"
require "./web_env"
require "./etcd_client"
require "./block_helper"
require "./taskqueue_api"
require "./remote_git_client"
require "../scheduler/constants"
require "../scheduler/jobfile_operate"
require "../scheduler/redis_client"
require "../scheduler/elasticsearch_client"

require "../scheduler/renew_deadline"
require "../scheduler/submit_job"
require "../scheduler/find_job_boot"
require "../scheduler/find_next_job_boot"
require "../scheduler/close_job"
require "../scheduler/request_cluster_state"
require "../scheduler/update_job_parameter"
require "../scheduler/create_job_cpio"
require "../scheduler/download_file"
require "../scheduler/opt_job_in_etcd"
require "../scheduler/report_event"

class Sched
  property es
  property redis
  property block_helper

  @@block_helper = BlockHelper.new

  def initialize(env : HTTP::Server::Context)
    @es = Elasticsearch::Client.new
    Redis::Client.set_pool_size(1000)
    @redis = Redis::Client.instance
    @mq = MQClient.instance
    @task_queue = TaskQueueAPI.new
    @etcd = EtcdClient.new
    @rgc = RemoteGitClient.new
    @env = env
    @log = env.log.as(JSONLogger)
  end

  def debug_message(response)
    @log.info(%({"from": "#{@env.request.remote_address}", "response": #{response.to_json}}))
  end

  def etcd_close
    @etcd.close
  end

  def alive(version)
    "LKP Alive! The time is #{Time.local}, version = #{version}"
  rescue e
    @log.warn(e.inspect_with_backtrace)
  end

  def normalize_mac(mac : String)
    mac.gsub(":", "-")
  end

  def set_host_mac
    if (hostname = @env.params.query["hostname"]?) && (mac = @env.params.query["mac"]?)
      @redis.hash_set("sched/mac2host", normalize_mac(mac), hostname)

      "Done"
    else
      "No yet!"
    end
  rescue e
    @log.warn(e.inspect_with_backtrace)
  end

  def del_host_mac
    if mac = @env.params.query["mac"]?
      @redis.hash_del("sched/mac2host", normalize_mac(mac))

      "Done"
    else
      "No yet!"
    end
  rescue e
    @log.warn(e.inspect_with_backtrace)
  end

  def set_host2queues
    if (queues = @env.params.query["queues"]?) && (hostname = @env.params.query["host"]?)
      @redis.hash_set("sched/host2queues", hostname, queues)

      "Done"
    else
      "No yet!"
    end
  rescue e
    @log.warn(e.inspect_with_backtrace)
  end

  def del_host2queues
    if hostname = @env.params.query["host"]?
      @redis.hash_del("sched/host2queues", hostname)

      "Done"
    else
      "No yet!"
    end
  rescue e
    @log.warn(e.inspect_with_backtrace)
  end

  def get_time
    Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
  end

  def update_tbox_wtmp
    testbox = ""
    hash = Hash(String, String | Nil).new

    hash["time"] = get_time

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
    @es.update_tbox(testbox, hash)

    # json log
    hash["testbox"] = testbox
    @log.info(hash.to_json)
  rescue e
    @log.warn(e.inspect_with_backtrace)
  end

  def send_mq_msg
    job_stage = @env.get?("job_stage").to_s
    deadline = @env.get?("deadline").to_s

    # the state of the testbox
    state = @env.get?("state").to_s

    # only need send job_stage info
    return if job_stage.empty?

    # because when the testbox in the requesting state
    # there is no deadline
    # other scenarios must have deadline
    return if deadline.empty? && state != "requesting"

    mq_msg = {
      "job_id" => @env.get?("job_id").to_s,
      "testbox" => @env.get?("testbox").to_s,
      "deadline" => deadline,
      "time" => get_time,
      "job_stage" => job_stage
    }
    spawn mq_publish_confirm(JOB_MQ, mq_msg.to_json)
  end

  # input:  ["sched/dc-8g.aarch64/ready"]
  # output: ["dc-8g.aarch64"]
  def fetch_queues(queues)
    new_queues = [] of String
    queues.each do |queue|
      new_queues << queue.split("/")[1]
    end
    new_queues
  end

  def set_lifecycle(job, testbox, queues)
    if job
      deadline = job.set_deadline("boot")
      job["job_state"] = "boot"
      job["job_stage"] = "boot"
      state = "booting"
      job_id = job["id"]
    else
      deadline = nil
      job_id = ""
      state = "requesting"
    end

    tbox_group = JobHelper.match_tbox_group(testbox.to_s)
    type = get_type(testbox)
    queues = JSON.parse(fetch_queues(queues).to_json)
    hash = {
      "job_id" => job_id,
      "state" => state,
      "time" => get_time,
      "deadline" => deadline,
      "queues" => queues,
      "type" => type,
      "name" => testbox,
      "tbox_group" => tbox_group
    }

    @redis.update_wtmp(testbox.to_s, hash)
    @es.update_tbox(testbox.to_s, hash)
  end

  def get_type(testbox)
    return unless testbox

    if testbox.includes?("vm")
      type = "vm"
    elsif testbox.includes?("dc")
      type = "dc"
    else
      type = "physical"
    end
    type
  end

  def report_ssh_port
    testbox = @env.params.query["tbox_name"]
    ssh_port = @env.params.query["ssh_port"].to_s
    job_id = @env.params.query["job_id"].to_s

    if testbox && ssh_port
      @redis.hash_set("sched/tbox2ssh_port", testbox, ssh_port)
    end

    @log.info(%({"job_id": "#{job_id}", "state": "set ssh port", "ssh_port": "#{ssh_port}", "tbox_name": "#{testbox}"}))
  rescue e
    @log.warn(e.inspect_with_backtrace)
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

  def mq_publish_confirm(queue, msg)
    3.times do
      @mq.publish_confirm(queue, msg)
      break
    rescue e
      @mq.reconnect
      sleep 5
    end
  end
end
