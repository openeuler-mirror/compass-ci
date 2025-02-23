# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"
require "yaml"
require "any_merge"

require "./job.cr"
require "./lib/utils.cr"
require "./lib/block_helper.cr"
require "./lib/remote_git_client.cr"
require "./lib/constants.cr"
require "./constants.cr"
require "./jobfile_operate.cr"
require "./lib/redis_client.cr"
require "./elasticsearch_client.cr"

require "./auto_depend_submit_job.cr"
require "./find_job_boot.cr"
require "./hw_find_job_boot.cr"
require "./cancel_jobs.cr"
require "./update_job_parameter.cr"
require "./set_srpm_info.cr"
require "./create_job_cpio.cr"
require "./download_file.cr"
require "./report_event.cr"
require "./report_ssh.cr"
require "./rpmbuild.cr"
require "./report_job_step.cr"
require "./pkgbuild.cr"
require "./cluster.cr"
require "./heart_beat.cr"
require "./dispatch.cr"
require "./hub.cr"
require "./lifecycle.cr"
require "./ipmi_console.cr"
require "./dashboard/jobs.cr"
require "./dashboard/hosts.cr"
require "./dashboard/accounts.cr"
require "./extract-stats/stats_worker.cr"
require "./options.cr"

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
  property accounts_cache

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

  def alive(version : String) : String
    "Compass CI scheduler is alive. Time: #{Time.local}, Version: #{version}"
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

  def api_get_host(hostname : String) : HostInfo?
    # Fetch host information from cache
    host_info = @hosts_cache.get_host(hostname)

    # Return nil if host is not found
    return nil unless host_info

    # Return host information
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
