# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def report_job_step
    job_id = @env.params.query["job_id"]?.to_s
    job_step = @env.params.query["job_step"]?.to_s

    @env.set "job_id", job_id
    @env.set "job_step", job_step

    check_params({"job_id" => job_id, "job_step" => job_step})

    job = @es.get_job(job_id.to_s)
    raise "can't faind this job in es: #{job_id}" unless job

    report_workflow_job_event(job, job_step)

  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  ensure
    send_mq_msg
  end

  def pack_job_event(job, event_type, job_step)
    workflow_exec_id = job["workflow_exec_id"]?.to_s
    job_stage = job["job_stage"]?.to_s
    
    job_name_regex = /\/(\w+)\.(yaml|yml|YAML|YML)$/
    job_name_match = regex.match(job_name_regex)
    job_name = job_name_match ? job_name_match[1] : nil

    return {} if job_name.nil?

    fingerprint = {
      "type" => event_type,
      "job" => job_name,
      "workflow_exec_id" => workflow_exec_id,
    }

    job_nickname = job["nickname"]?.to_s

    fingerprint = fingerprint.merge({"nickname" => job_nickname}) if job_nickname.nil? || job_nickname.empty?

    if event_type == "job/stage"
      fingerprint.merge({
        "job_stage" => job_stage,
        "job_health" => job_health,
      })
    elsif event_type == "job/step"
      fingerprint.merge({
        "job_step" => step,
      })
    else
      return {}
    end

    job.merge(fingerprint)
  end

  def report_workflow_job_event(job, job_step)
    return if job["workflow_exec_id"].nil? || job["workflow_exec_id"].empty?

    event_type = step.nil? ? "job/stage" : "job/step"
    event = pack_job_event(job, event_type, job_step)
    @etcd.put_not_exist("raw_events/job/#{job_id}", event.to_json)
  end
end