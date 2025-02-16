# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def api_hw_find_job_boot(env)
    # Extract parameters from the environment
    mac = env.params.query["mac"]? || env.params.url["value"]
    ip = env.params.query["ip"]?

    boot_type = env.params.query["boot_type"]? || env.params.url["boot_type"]
    host = env.params.query["hostname"]?
    arch = env.params.query["arch"]?
    tags = env.params.query["tags"]? # format: tag1,tag2,...
    pre_job_id = env.params.query["pre_job_id"]?

    # Normalize MAC address and resolve hostname if necessary
    mac = Utils.normalize_mac(mac)
    host ||= @hosts_cache.mac2hostname(mac)
    return boot_content(nil, boot_type) unless host

    arch ||= @hosts_cache[host].arch
    host_req = HostRequest.new(arch, host, "hw", tags, @hosts_cache[host].memory, false)
    job = tbox_request_job(host_req)
    job ||= hw_wait_job(host)
    return hw_boot_msg(boot_type, "No job now") unless job

    job.hostname = host
    on_job_dispatch(job, host_req)
    response = boot_content(job, boot_type)
  end

  def hw_wait_job(host_machine)
    if @hw_machine_channels.has_key? host_machine
      channel = @hw_machine_channels[host_machine]
    else
      channel = @hw_machine_channels[host_machine] = Channel(JobHash).new
    end

    job = nil
    select
    # add_job_to_cache() checks @hw_machine_channels
    # => @host_request_job_channel.send
    # => dispatch_worker/collect_host_requests()
    # => dispatch_worker/find_dispatch_jobs()
    # => dispatch_job() to us
    when job = channel.receive
    when timeout(10.seconds)
    end
    @hw_machine_channels.delete host_machine
    return job
  end

end
