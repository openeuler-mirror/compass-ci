# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"

class Sched
  def report_job_step
    job_id = @env.params.query["job_id"]?.to_s
    job_step = @env.params.query["job_step"]?.to_s

    @env.set "job_id", job_id
    @env.set "job_step", job_step

    check_params({"job_id" => job_id, "job_step" => job_step})

    job = @es.get_job(job_id.to_s)
    raise "can't find this job in es: #{job_id}" unless job

    report_workflow_job_event(job_id, job, job_step)

  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  ensure
    send_mq_msg
  end

  def pack_job_event(job_id, job, event_type, job_step)
    return unless event_type == "job/stage" || event_type == "job/step"

    workflow_exec_id = job["workflow_exec_id"]?.to_s
    return if workflow_exec_id.nil? || workflow_exec_id.empty?

    job_name_regex = /\/([^\/]+)\.(yaml|yml|YAML|YML)$/
    job_origin = job["job_origin"]?.to_s
    return if job_origin.nil? || job_origin.empty?

    job_name_match = job_origin.match(job_name_regex)
    job_name = job_name_match ? job_name_match[1] : nil
    return unless !job_name.nil?

    job_stage = job["job_stage"]?.to_s
    job_health = job["job_health"]?.to_s
    job_result = job["result_root"]?.to_s
    job_nickname = job["nickname"]?.to_s
    job_matrix = job["matrix"]?.to_s
    job_branch = job["branch"]?.to_s
    
    fingerprint = {
      "type" => event_type,
      "job" => job_name,
      "workflow_exec_id" => workflow_exec_id,
    }
    fingerprint = fingerprint.merge({"nickname" => job_nickname}) if !job_nickname.nil? && !job_nickname.empty?

    if event_type == "job/stage"
      fingerprint = fingerprint.merge({
        "job_stage" => job_stage,
        "job_health" => job_health,
      })
    elsif event_type == "job/step"
      fingerprint = fingerprint.merge({
        "job_step" => job_step,
      })
    end
    
    {
      "fingerprint" => fingerprint,
      "job_id" => job_id,
      "job" => job_name,
      "type" => event_type,
      "job_stage" => job_stage,
      "job_health" => job_health,
      "nickname" => job_nickname,
      "matrix" => job_matrix,
      "branch" => job_branch,
      "result_root" => job_result,
      "workflow_exec_id" => workflow_exec_id,
    }
  end

  def report_workflow_job_event(job_id, job, job_step=nil)
    event_type = job_step.nil? ? "job/stage" : "job/step"
    event = pack_job_event(job_id, job, event_type, job_step)
    return unless !event.nil?

    @etcd.put_not_exists("raw_events/job/#{job_id}", event.to_json)
    @log.info({
      "message" => event,
    }.to_json)
  end
end
