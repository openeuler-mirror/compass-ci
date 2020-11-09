# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"
require "yaml"

require "./job"
require "./block_helper"
require "./taskqueue_api"
require "./remote_git_client"
require "../scheduler/constants"
require "../scheduler/jobfile_operate"
require "../scheduler/redis_client"
require "../scheduler/elasticsearch_client"

require "../scheduler/find_job_boot"
require "../scheduler/find_next_job_boot"
require "../scheduler/close_job"
require "../scheduler/request_cluster_state"

class Sched
  property es
  property redis
  property block_helper

  def initialize
    @es = Elasticsearch::Client.new
    @redis = Redis::Client.new
    @task_queue = TaskQueueAPI.new
    @block_helper = BlockHelper.new
    @rgc = RemoteGitClient.new
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

  # get cluster config using own lkp_src cluster file,
  # a hash type will be returned
  def get_cluster_config(cluster_file, lkp_initrd_user, os_arch)
    lkp_src = Jobfile::Operate.prepare_lkp_tests(lkp_initrd_user, os_arch)
    cluster_file_path = Path.new(lkp_src, "cluster", cluster_file)
    return YAML.parse(File.read(cluster_file_path))
  end

  def get_commit_date(job)
    if (job["upstream_repo"] != "") && (job["upstream_commit"] != "")
      data = JSON.parse(%({"git_repo": "#{job["upstream_repo"]}.git",
                   "git_command": ["git-log", "--pretty=format:%cd", "--date=unix",
                   "#{job["upstream_commit"]}", "-1"]}))
      response = @rgc.git_command(data)
      return response.body if response.status_code == 200
    end

    return nil
  end

  def submit_job(env : HTTP::Server::Context)
    body = env.request.body.not_nil!.gets_to_end

    job_content = JSON.parse(body)
    job = Job.new(job_content, job_content["id"]?)
    job["commit_date"] = get_commit_date(job)

    # it is not a cluster job if cluster field is empty or
    # field's prefix is 'cs-localhost'
    cluster_file = job["cluster"]
    if cluster_file.empty? || cluster_file.starts_with?("cs-localhost")
      return submit_single_job(job)
    else
      cluster_config = get_cluster_config(cluster_file,
        job.lkp_initrd_user,
        job.os_arch)
      return submit_cluster_job(job, cluster_config)
    end
  rescue ex
    puts ex.inspect_with_backtrace
    return [{
      "job_id"    => "0",
      "message"   => ex.to_s,
      "job_state" => "submit",
    }]
  end

  # return:
  #   success: [{"job_id" => job_id1, "message => "", "job_state" => "submit"}, ...]
  #   failure: [..., {"job_id" => 0, "message" => err_msg, "job_state" => "submit"}]
  def submit_cluster_job(job, cluster_config)
    job_messages = Array(Hash(String, String)).new
    lab = job.lab

    # collect all job ids
    job_ids = [] of String

    net_id = "192.168.222"
    ip0 = cluster_config["ip0"]?
    if ip0
      ip0 = ip0.as_i
    else
      ip0 = 1
    end

    # steps for each host
    cluster_config["nodes"].as_h.each do |host, config|
      tbox_group = host.to_s
      job_id = add_task(tbox_group, lab)

      # return when job_id is '0'
      # 2 Questions:
      #   - how to deal with the jobs added to DB prior to this loop
      #   - may consume job before all jobs done
      return job_messages << {
        "job_id"    => "0",
        "message"   => "add task queue sched/#{tbox_group} failed",
        "job_state" => "submit",
      } unless job_id

      job_ids << job_id

      # add to job content when multi-test
      job["testbox"] = tbox_group
      job.update_tbox_group(tbox_group)
      job["node_roles"] = config["roles"].as_a.join(" ")
      direct_macs = config["macs"].as_a
      direct_ips = [] of String
      direct_macs.size.times do
        raise "Host id is greater than 254, host_id: #{ip0}" if ip0 > 254
        direct_ips << "#{net_id}.#{ip0}"
        ip0 += 1
      end
      job["direct_macs"] = direct_macs.join(" ")
      job["direct_ips"] = direct_ips.join(" ")

      response = add_job(job, job_id)
      message = (response["error"]? ? response["error"]["root_cause"] : "")
      job_messages << {
        "job_id"      => job_id,
        "message"     => message.to_s,
        "job_state"   => "submit",
        "result_root" => "/srv#{job.result_root}",
      }
      return job_messages if response["error"]?
    end

    cluster_id = job_ids[0]

    # collect all host states
    cluster_state = Hash(String, Hash(String, String)).new
    job_ids.each do |job_id|
      cluster_state[job_id] = {"state" => ""}
      # will get cluster id according to job id
      @redis.hash_set("sched/id2cluster", job_id, cluster_id)
    end

    @redis.hash_set("sched/cluster_state", cluster_id, cluster_state.to_json)

    return job_messages
  end

  # return:
  #   success: [{"job_id" => job_id, "message" => "", job_state => "submit"}]
  #   failure: [{"job_id" => "0", "message" => err_msg, job_state => "submit"}]
  def submit_single_job(job)
    queue = job.queue
    return [{
      "job_id"    => "0",
      "message"   => "get queue failed",
      "job_state" => "submit",
    }] unless queue

    # only single job will has "idle job" and "execute rate limiter"
    if job["idle_job"].empty?
      queue += "#{job.get_uuid_tag}"
    else
      queue = "#{queue}/idle"
    end

    job_id = add_task(queue, job.lab)
    return [{
      "job_id"    => "0",
      "message"   => "add task queue sched/#{queue} failed",
      "job_state" => "submit",
    }] unless job_id

    response = add_job(job, job_id)
    message = (response["error"]? ? response["error"]["root_cause"] : "")

    return [{
      "job_id"      => job_id,
      "message"     => message.to_s,
      "job_state"   => "submit",
      "result_root" => "/srv#{job.result_root}",
    }]
  end

  # return job_id
  def add_task(queue, lab)
    task_desc = JSON.parse(%({"domain": "compass-ci", "lab": "#{lab}"}))
    response = @task_queue.add_task("sched/#{queue}", task_desc)
    JSON.parse(response[1].to_json)["id"].to_s if response[0] == 200
  end

  # add job content to es and return a response
  def add_job(job, job_id)
    job.update_id(job_id)
    @es.set_job_content(job)
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

  def update_job_parameter(env : HTTP::Server::Context)
    job_id = env.params.query["job_id"]?
    if !job_id
      return false
    end

    # try to get report value and then update it
    job_content = {} of String => String
    job_content["id"] = job_id

    (%w(start_time end_time loadavg job_state)).each do |parameter|
      value = env.params.query[parameter]?
      if !value || value == ""
        next
      end
      if parameter == "start_time" || parameter == "end_time"
        value = Time.unix(value.to_i).to_local.to_s("%Y-%m-%d %H:%M:%S")
      end

      job_content[parameter] = value
    end

    @redis.update_job(job_content)

    # json log
    log = job_content.dup
    log["job_id"] = log.delete("id").not_nil!
    return log.to_json
  end

  def update_tbox_wtmp(env : HTTP::Server::Context)
    testbox = ""
    hash = Hash(String, String).new

    time = Time.local.to_s("%Y-%m-%d %H:%M:%S")
    hash["time"] = time

    %w(mac ip job_id tbox_name tbox_state).each do |parameter|
      if (value = env.params.query[parameter]?)
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
    return hash.to_json
  end

  def report_ssh_port(testbox : String, ssh_port : String)
    @redis.hash_set("sched/tbox2ssh_port", testbox, ssh_port)
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
