# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def hw_find_job_boot
    @env.set "job_stage", "boot"

    value = @env.params.url["value"]
    boot_type = @env.params.url["boot_type"]

    mac = normalize_mac(value)
    host = @redis.hash_get("sched/mac2host", mac)
    return boot_content(nil, boot_type) unless host

    set_hw_tbox_to_redis(host)

    @env.set "testbox", host unless host.nil?

    response = hw_get_job_boot(host, boot_type)

    job_id = response[/tmpfs\/(.*)\/job\.cgz/, 1]?
    @env.set "job_id", job_id

    response
  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  ensure
    del_hw_tbox_from_redis
    send_mq_msg
  end

  def set_hw_tbox_to_redis(host)
    data = Hash(String, String).new
    data["type"] = "hw"
    data["hostname"] = "#{host}"

    data["arch"] = "x86_64"
    data["arch"] = "aarch64" if host.starts_with?("taishan")

    data["max_mem"] = "16"
    max_mem = /-(\d+)g--/.match(host)
    data["max_mem"] = "#{max_mem[1]}" if max_mem

    tbox =  "/tbox/#{data["type"]}/#{data["hostname"]}"
    @redis.set(tbox, data.to_json)
    @redis.expire(tbox, 600)

    @env.set "redis_tbox", tbox
  end

  def del_hw_tbox_from_redis
    tbox = @env.get "redis_tbox"
    @redis.del("#{tbox}") if tbox
  end

  def hw_get_job_from_ready_queues(boot_type, host_machine)
    etcd_job = nil
    return etcd_job if host_machine.nil?

    @log.info("hw get job from ready queues by host_machine: #{host_machine}")
    60.times do |_i|
      etcd_job = GetJob.new.get_job_by_tbox_type(host_machine, "hw")
      @log.info("GetJob.new.get_job_by_tbox_type #{host_machine}, hw, return: #{etcd_job}")
      break if etcd_job
      sleep 10.seconds
    end

    return etcd_job["id"]? if etcd_job
    return nil
  end

  def hw_get_job_boot(host, boot_type, pre_job=nil)
    @env.set "state", "requesting"
    send_mq_msg
    host_machine = host

    job_id = hw_get_job_from_ready_queues(boot_type, host_machine)
    @log.info("hw get job from ready queues boot_type: #{boot_type}, host_machine: #{host_machine}, return: #{job_id}")

    job = @es.get_job(job_id.to_s) if job_id

    if job
      @log.info("#{host} got the job #{job_id}")
      update_testbox_and_job(job, host, ["//#{host}"]) if job

      job.update({"testbox" => host, "host_machine" => host_machine})
      job.update_kernel_params
      job.set_result_root
      job.set_time("boot_time")
      @log.info(%({"job_id": "#{job_id}",
                "result_root": "/srv#{job.result_root}",
                "job_state": "set result root"}))

      update_id2job(job)

      job["last_success_stage"] = "boot"
      @es.set_job(job)

      report_workflow_job_event(job["id"].to_s, job)

      @env.set "job_id", job.id
      @env.set "deadline", job.deadline
      @env.set "job_stage", job.job_stage
      @env.set "state", "booting"
      create_job_cpio(job, Kemal.config.public_folder)
      set_id2upload_dirs(job)
    end

    return job ? get_boot_ipxe(job) : boot_msg(boot_type, "No job now")
  end
end
