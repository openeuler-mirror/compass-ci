# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"
require "yaml"
require "any_merge"

require "./job"
require "./utils"
require "./block_helper"
require "./remote_git_client"
require "./constants"
require "../scheduler/constants"
require "../scheduler/jobfile_operate"
require "../scheduler/redis_client"
require "../scheduler/elasticsearch_client"

require "../scheduler/auto_depend_submit_job"
require "../scheduler/find_job_boot"
require "../scheduler/hw_find_job_boot"
require "../scheduler/cancel_jobs"
require "../scheduler/update_job_parameter"
require "../scheduler/set_srpm_info"
require "../scheduler/create_job_cpio"
require "../scheduler/download_file"
require "../scheduler/report_event"
require "../scheduler/report_ssh"
require "../scheduler/rpmbuild"
require "../scheduler/report_job_step"
require "../scheduler/plugins/pkgbuild"
require "../scheduler/plugins/cluster"
require "../scheduler/heart_beat"
require "../scheduler/dispatch"
require "../scheduler/hub"
require "../scheduler/lifecycle"
require "../scheduler/ipmi_console"
require "../extract-stats/stats_worker"
require "../scheduler/options"

def sched
  Scheduler.sched
end

class Sched

  property es
  property redis
  property block_helper
  property cluster
  property pkgbuild
  property hosts_cache

  class_property options = SchedOptions.new

  @@block_helper = BlockHelper.new

  @@instance : self?

  def self.instance : self
    @@instance ||= new
  end

  def initialize()
    @es = Elasticsearch::Client.new
    @redis = RedisClient.instance
    @rgc = RemoteGitClient.new
    @log = JSONLogger.new
    @cluster = Cluster.new
    @pkgbuild = PkgBuild.new
    # Load initial hosts data from ES
    @hosts_cache = Hosts.new(@es)
    @accounts_cache = Accounts.new(@es)
    refresh_cache_from_es
    setup_serial_consoles
    @stats_worker = StatsWorker.new
  end

  def debug_message(env, response)
    @log.info(%({"from": "#{env.request.remote_address}", "response": #{response.to_json}}))
  end

  def alive(version)
    "LKP Alive! The time is #{Time.local}, version = #{version}"
  rescue e
    @log.warn(e.inspect_with_backtrace)
  end

  def get_time
    Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
  end

  def send_mq_msg(env)
    job_stage = env.get?("job_stage").to_s
    deadline = env.get?("deadline").to_s

    # the state of the testbox
    state = env.get?("state").to_s

    # only need send job_stage info
    return if job_stage.empty?

    # because when the testbox in the requesting state
    # there is no deadline
    # other scenarios must have deadline
    return if deadline.empty? && state != "requesting"

    mq_msg = {
      "job_id" => env.get?("job_id").to_s,
      "testbox" => env.get?("testbox").to_s,
      "deadline" => deadline,
      "time" => get_time,
      "job_stage" => job_stage
    }
    json_str = mq_msg.to_json

    unless mq_msg["job_id"].empty?
      send_job_event(mq_msg["job_id"].to_i64, json_str)
    end
  end

  def get_api(env)
    resource = env.request.resource
    api = resource.split("?")[0].split("/")
    if resource.starts_with?("/boot.")
      return "boot"
    elsif resource.starts_with?("/job_initrd_tmpfs")
      return api[1]
    else
      return api[-1]
    end
  end

  def get_host_machine(testbox)
    return testbox unless testbox =~ /^(vm-|dc-)/

    # dc-16g.taishan200-2280-2s64p-256g--a1001-1252549 => taishan200-2280-2s64p-256g--a1001
    testbox.split(".")[1].reverse.split("-", 2)[1].reverse
  end

  def api_get_host(hostname : String)
    host_info = @hosts_cache.get_host(hostname)
    raise "cant find the testbox in es, hostname: #{hostname}" unless host_info
    host_info
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

end
