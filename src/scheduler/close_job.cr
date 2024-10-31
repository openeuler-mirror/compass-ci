# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def update_job_resource(job, mem, cpu)
    return unless mem
    return unless cpu

    begin
      index = "job_resource"
      if ["rpmbuild", "hotpatch"].includes?("#{job.suite}")
        id = "#{job.suite}_#{job.arch}_#{job.os_project}_#{job.package}_#{job.spec_file_name}"
      else
        return
      end
      content = { "mem" => mem, "cpu" => cpu }
      @es.set_content_by_id(index, id, content)
    rescue e
      @log.warn({
        "message" => e.to_s,
        "error_message" => e.inspect_with_backtrace.to_s
      }.to_json)
    end
  end

  def update_wait_job_by_ss(job)
    job_waited = job.waited?
    return unless job_waited

    job_waited.not_nil!.each do |k, v|
      k_job = @es.get_job(k)
      next unless k_job
      next unless k_job.ss_wait_jobs?

      k_job.ss_wait_jobs.not_nil!.merge!({job.id => job.job_health})
      k_job.job_health = job.job_health if job.job_health != "success"
      @es.set_job(k_job)
    end
  end

  def close_job
    job_id = @env.params.query["job_id"]?
    mem = @env.params.query["mem"]?
    cpu = @env.params.query["cpu"]?
    return unless job_id

    @env.set "job_id", job_id
    @env.set "job_stage", "finish"

    # etcd id2job only stores partial job content
    # so query full job from es
    job = @es.get_job(job_id)
    raise "can't find job from es, job_id: #{job_id}" unless job

    # update job content
    job_state = @env.params.query["job_state"]?
    job.job_state = job_state if job_state
    job.job_state = "complete" if job.job_state == "boot"

    job.job_stage = "finish"

    job_health = @env.params.query["job_health"]?
    if job_health && job_health == "return"
      # if user returns this testbox
      # job_health needs to be return
      job.job_health = job_health
    else
      unless job.has_key?("job_health")
        job.job_health = (job_health || "success")
      end
    end

    if job.job_health == "success" || job.job_health == "oom"
      # update job resource
      update_job_resource(job, mem, cpu)
    end

    if job.job_health != "success"
      if job.has_key?("snapshot_id") && !job.snapshot_id.empty?
        data = {"build_id" => job.build_id, "job_id" => job.id, "build_type" => job.build_type, "emsx" => job.emsx}
        @etcd.put_not_exists("update_jobs/#{job.id}", data.to_json)
      end
    end

    job.set_time("finish_time")
    @env.set "finish_time", job.finish_time

    if job.has_key?("running_time") && job.has_key?("finish_time")
      running_time = Time.parse(job.running_time, "%Y-%m-%dT%H:%M:%S", Time.local.location)
      finish_time = Time.parse(job.finish_time, "%Y-%m-%dT%H:%M:%S", Time.local.location)
      job.run_seconds = (finish_time - running_time).to_s
    end

    if @env.params.query["source"]? != "lifecycle"
      deadline = job.get_deadline("finish")
      @env.set "deadline", deadline.to_s
      @es.update_tbox(job.testbox, {"deadline" => deadline})
      job.last_success_stage = "finish"
    end

    set_job2watch(job, "close", job.job_health)
    update_wait_job_by_ss(job)


    response = @es.set_job(job)
    if response["_id"] == nil
      # es update fail, raise exception
      raise "es set job content fail!"
    end

    report_workflow_job_event(job_id.to_s, job)
    "success"
  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
    e.to_s
  ensure
    send_mq_msg if @env.params.query["source"]? != "lifecycle"
    if job
      # need update the end job_health to etcd
      res = update_id2job(job)
      @log.info("scheduler update job to id2job #{job.id}: #{res}")
      res = move_process2extract(job)
      @log.info("scheduler move in_process to extract_stats #{job.id}: #{res}")
    end
  end
end
