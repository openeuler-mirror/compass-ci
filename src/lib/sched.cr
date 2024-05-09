# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"
require "yaml"
require "any_merge"

require "./mq"
require "./job"
require "./utils"
require "./web_env"
require "./etcd_client"
require "./block_helper"
require "./remote_git_client"
require "./constants"
require "../scheduler/constants"
require "../scheduler/jobfile_operate"
require "../scheduler/redis_client"
require "../scheduler/elasticsearch_client"

require "../scheduler/renew_deadline"
require "../scheduler/auto_depend_submit_job"
require "../scheduler/find_job_boot"
require "../scheduler/hw_find_job_boot"
require "../scheduler/find_next_job_boot"
require "../scheduler/close_job"
require "../scheduler/cancel_jobs"
require "../scheduler/update_subqueues"
require "../scheduler/request_cluster_state"
require "../scheduler/update_job_parameter"
require "../scheduler/set_job_stage"
require "../scheduler/set_srpm_info"
require "../scheduler/create_job_cpio"
require "../scheduler/download_file"
require "../scheduler/opt_job_in_etcd"
require "../scheduler/report_event"
require "../scheduler/report_ssh"
require "../scheduler/rpmbuild"
require "../scheduler/report_job_step"
require "../scheduler/plugins/pkgbuild"
require "../scheduler/plugins/finally"
require "../scheduler/plugins/cluster"
require "../scheduler/heart_beat"

class Sched
  property es
  property redis
  property block_helper

  @@block_helper = BlockHelper.new

  def initialize(env : HTTP::Server::Context)
    @es = Elasticsearch::Client.new
    @redis = RedisClient.instance
    @mq = MQClient.instance
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
    mac.gsub(":", "-").downcase()
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

  def register_host2redis
    type = @env.params.query["type"]
    data = Hash(String, String).new
    data["type"] = type
    data["arch"] = @env.params.query["arch"]
    data["owner"] = @env.params.query["owner"]
    data["max_mem"] = @env.params.query["max_mem"]
    data["hostname"] = @env.params.query["hostname"]
    data["is_remote"] = @env.params.query["is_remote"]


    unless TBOX_TYPES.includes?(type)
      @log.warn("type is not support, type: #{type}")
      raise "type is not support, type: #{type}"
    end

    hostname = "local-#{data["hostname"]}"
    hostname = data["is_remote"] == "true"? "remote-#{data["hostname"]}" : hostname
    data["hostname"] = hostname

    tbox = "/tbox/#{type}/#{data["hostname"]}"
    @redis.set(tbox, data.to_json )
    @redis.expire(tbox, 60)
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

  # input:  ["sched/ready/$queue/$subqueue/$id"]
  # output: ["$queue"]
  def fetch_queues(queues)
    new_queues = [] of String
    queues.each do |queue|
      new_queues << queue.split("/")[2]
    end
    new_queues
  end

  def get_api
    resource = @env.request.resource
    api = resource.split("?")[0].split("/")
    if resource.starts_with?("/boot.")
      return "boot"
    elsif resource.starts_with?("/job_initrd_tmpfs")
      return api[1]
    else
      return api[-1]
    end
  end

  def update_job_when_boot(job)
    return unless job

    job.set_deadline("boot")
    job.job_state = "boot"
    job.job_stage = "boot"
  end

  def update_testbox_boot_info(job, hash)
    return hash unless job

    hash["deadline"] = job.deadline
    hash["job_id"] = job.id
    hash["suite"] = job.suite
    hash["my_account"] = job.my_account
    hash["result_root"] = job.result_root
    hash["state"] = "booting"
    hash["timeout_period"] = job.timeout
    hash["arch"] = job.os_arch
    hash["hostname"] = job.host_machine
    hash["type"] = job.tbox_type
  end

  def update_testbox_and_job(job, testbox, queues)
    hash = {
      "deadline" => nil,
      "job_id" => "",
      "state" => "requesting",
      "suite" => nil,
      "my_account" => nil,
      "time" => get_time,
      "queues" => JSON.parse(fetch_queues(queues).to_json),
      "type" => get_type(testbox),
      "name" => testbox,
      "tbox_group" => JobHelper.match_tbox_group(testbox.to_s),
      "hostname" => get_host_machine(testbox.to_s),
      "timeout_period" => "1800",
      "arch" => get_testbox_arch(testbox.to_s)
    }
    update_job_when_boot(job)
    update_testbox_boot_info(job, hash)

    @redis.update_wtmp(testbox.to_s, hash)
    @es.update_tbox(testbox.to_s, hash)
  end

  def get_host_machine(testbox)
    return testbox unless testbox =~ /^(vm-|dc-)/

    # dc-16g.taishan200-2280-2s64p-256g--a1001-1252549 => taishan200-2280-2s64p-256g--a1001
    testbox.split(".")[1].reverse.split("-", 2)[1].reverse
  end

  def get_testbox_arch(testbox)
    host_machine = get_host_machine(testbox)
    host_machine_file = "#{CCI_REPOS}/#{LAB_REPO}/hosts/#{host_machine}"
    return "unknown" unless File.exists?(host_machine_file)

    host_machine_info = YAML.parse(File.read(host_machine_file)).as_h
    return host_machine_info["arch"].to_s
  rescue e
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s,
      "testbox" => testbox
    }.to_json)
    "unknown"
  end

  def get_testbox
    testbox = @env.params.query["testbox"]?.to_s
    testbox_info = @es.get_tbox(testbox)
    raise "cant find the testbox in es, testbox: #{testbox}" unless testbox_info

    testbox_info
  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)

    return Hash(String, JSON::Any).new
  end

  def get_type(testbox)
    return unless testbox

    if testbox.starts_with?("vm-")
      type = "vm"
    elsif testbox.starts_with?("dc-")
      type = "dc"
    else
      type = "physical"
    end
    type
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
