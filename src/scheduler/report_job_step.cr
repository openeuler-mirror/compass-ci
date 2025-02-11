# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"

class Sched

  def pack_job_event(job_id, job, event_type, job_step, only_stage = false)
    return unless event_type == "job/stage" || event_type == "job/step"

    workflow_exec_id = job.workflow_exec_id?
    return if workflow_exec_id.nil? || workflow_exec_id.empty?

    job_name_regex = /\/([^\/]+)\.(yaml|yml|YAML|YML)$/
    job_origin = job.job_origin?
    return if job_origin.nil? || job_origin.empty?

    job_name_match = job_origin.match(job_name_regex)
    job_name = job_name_match ? job_name_match[1] : nil
    return unless !job_name.nil?

    job_stage = job.job_stage?
    job_health = job.job_health?
    job_result = job.result_root?
    job_nickname = job.nickname?
    
    begin
      job_matrix = job.matrix?
      job_matrix = job.matrix?.to_json
    rescue
    end

    job_branch = job.branch?

    # TODO the root reason could be a bug of lkp-tests
    # avoid job_stage is running but job_health is success or failed
    if job_health == "success" || job_health == "failed"
      job_stage = "finish"
    end
    
    fingerprint = {
      "type" => event_type,
      "job" => job_name,
      "workflow_exec_id" => workflow_exec_id,
    }
    fingerprint = fingerprint.merge({"nickname" => job_nickname}) if !job_nickname.nil? && !job_nickname.empty?

    if event_type == "job/stage" && !only_stage
      fingerprint = fingerprint.merge({
        "job_stage" => job_stage,
        "job_health" => job_health,
      })
    elsif event_type == "job/stage"
      fingerprint = fingerprint.merge({
        "job_stage" => job_stage,
      })
    elsif event_type == "job/step"
      fingerprint = fingerprint.merge({
        "job_step" => job_step,
      })
    end
    
    packed_event = {
      "fingerprint" => fingerprint,
      "job_id" => job_id,
      "job" => job_name,
      "type" => event_type,
      "job_stage" => job_stage,
      "job_health" => job_health,
      "nickname" => job_nickname,
      "branch" => job_branch,
      "result_root" => job_result,
      "workflow_exec_id" => workflow_exec_id,
    }
    packed_event.merge!({"job_matrix" => job_matrix}) unless job_matrix.nil?

    packed_event
  end

  def report_workflow_job_event(job_id, job, job_step=nil)
    event_type = job_step.nil? ? "job/stage" : "job/step"
    if job.job_stage? == "finish"
      finish_event = pack_job_event(job_id, job, event_type, job_step, true)
      return unless !finish_event.nil?

      @etcd.put_not_exists("raw_events/job/#{job_id}/finish", finish_event.to_json)
      @log.info({
        "report_event" => finish_event,
      }.to_json)
    end
    event = pack_job_event(job_id, job, event_type, job_step)
    return unless !event.nil?

    @etcd.put_not_exists("raw_events/job/#{job_id}", event.to_json)
    @log.info({
      "report_event" => event,
    }.to_json)
  end
end
