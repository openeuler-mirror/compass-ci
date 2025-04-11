# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched

  def api_hw_find_job_boot(env)
    begin
      # Extract parameters from the environment with default values
      ip = env.params.query["ip"]?
      mac = env.params.query["mac"]? || env.params.url["value"]
      boot_type = env.params.query["boot_type"]? || env.params.url["boot_type"]
      host = env.params.query["hostname"]?
      arch = env.params.query["arch"]?
      tags = env.params.query["tags"]? || "" # format: tag1,tag2,...
      is_remote = (env.params.query["is_remote"]? == "true")
      pre_job_id = env.params.query["pre_job_id"]?
      sched_host = env.params.query["sched_host"]? || "172.17.0.1"
      sched_port = env.params.query["sched_port"]? || "3000"

      # Validate required parameters
      unless mac
        env.response.status_code = HTTP::Status::BAD_REQUEST.code
        return "Missing MAC address"
      end

      # Normalize MAC address and resolve hostname if necessary
      mac = Utils.normalize_mac(mac)
      host = @hosts_cache.mac2hostname[mac]?

      host = host.to_s
      if host.empty?
        env.response.status_code = HTTP::Status::NOT_FOUND.code
        return boot_content(nil, boot_type)
      end

      # Set default architecture if not provided
      arch ||= @hosts_cache[host].arch

      # Create a HostRequest object
      host_req = HostRequest.new(
        arch: arch,
        hostname: host,
        tbox_type: "hw",
        tags: tags,
        freemem: @hosts_cache[host].memory,
        is_remote: is_remote,
        # pre_job_id: pre_job_id,
        sched_host: sched_host,
        sched_port: sched_port
      )

      unless @hw_machine_channels.has_key? host
        @hw_machine_channels[host] = Channel(JobHash).new
      end

      # Attempt to find a job for the host
      #job = tbox_request_job(host_req) || hw_wait_job(host)
      job = tbox_request_job(host_req)

      unless job
        env.response.status_code = HTTP::Status::NOT_FOUND.code
        return hw_boot_msg(boot_type, "No job available at the moment")
      end

      # Update job details and dispatch
      on_job_dispatch(job, host_req)

      # Return the boot content
      boot_content(job, boot_type)

    rescue ex
      # Log the exception for debugging purposes
      @log.error(exception: ex) { "An error occurred in api_hw_find_job_boot" }

      # Set a HTTP::Status::INTERNAL_SERVER_ERROR Internal Server Error status code
      env.response.status_code = HTTP::Status::INTERNAL_SERVER_ERROR.code
      "An internal server error occurred. Please try again later."
    end
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
