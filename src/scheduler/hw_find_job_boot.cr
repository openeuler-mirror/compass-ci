# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def hw_find_job_boot(env)
    env.set "job_stage", "boot"

    value = env.params.url["value"]
    boot_type = env.params.url["boot_type"]
    host = env.params.url["hostname"]
    arch = env.params.url["arch"]
    tags = env.params.url["tags"] # format: tag1,tag2,...
    pre_job_id = env.params.url["pre_job_id"]?

    mac = Utils.normalize_mac(value)
    host ||= @hosts_cache.mac2hostname(mac)
    return boot_content(nil, boot_type) unless host

    env.set "testbox", host unless host.nil?

    response = hw_get_job_boot(env, host, arch, boot_type, tags, pre_job_id)

    job_id = response[/tmpfs\/(.*)\/job\.cgz/, 1]?
    env.set "job_id", job_id

    response
  rescue e
    env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  ensure
    send_mq_msg(env)
  end

  def hw_get_job_from_ready_queues(boot_type, arch, host_machine, tags)
    etcd_job = nil
    return etcd_job if host_machine.nil?

    @log.info("hw get job from ready queues by host_machine: #{host_machine}")

    host_req = HostRequest.new(arch, host_machine, "hw", tags, UInt32::MAX, false)

    etcd_job = tbox_request_job(host_req)
    etcd_job ||= hw_wait_job(host_machine)

    @log.info("tbox_request_job #{host_machine}, hw, return: #{etcd_job}")
    return etcd_job["id"]? if etcd_job
    return nil
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

  def hw_get_job_boot(env, host, arch, boot_type, tags, pre_job_id=nil)
    env.set "state", "requesting"
    send_mq_msg(env)
    host_machine = host

    job_id = hw_get_job_from_ready_queues(boot_type, arch, host_machine, tags)
    @log.info("hw get job from ready queues boot_type: #{boot_type}, host_machine: #{host_machine}, return: #{job_id}")

    job = @es.get_job(job_id.to_s) if job_id

    if job && job_id
      @log.info("#{host} got the job #{job_id}")

      job.update({"hostname" => host_machine, "tbox_type" => "hw", "host_machine" => host_machine})
      job.update_kernel_params
      job.set_result_root
      job.set_time("boot_time")
      @log.info(%({"job_id": "#{job_id}",
                "result_root": "/srv#{job.result_root}",
                "job_state": "set result root"}))

      @hosts_cache.update_job_info(job)

      job["last_success_stage"] = "boot"
      @es.set_job(job)

      report_workflow_job_event(job["id"].to_s, job)

      env.set "job_id", job.id
      env.set "deadline", job.deadline
      env.set "job_stage", job.job_stage
      env.set "state", "booting"
      create_job_cpio(job, Kemal.config.public_folder)
      set_id2upload_dirs(job)
    end

    return job ? get_boot_ipxe(job) : boot_msg(boot_type, "No job now")
  end
end
