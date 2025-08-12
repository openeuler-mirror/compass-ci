# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "time"

class Sched

  # API method to update a job based on query parameters
  def api_update_job(env : HTTP::Server::Context) : Result
    params = env.params.query.to_h
    params["job_id"] ||= env.params.url["job_id"]
    update_job_from_hash(params)
  end

  # Update job attributes from a hash of parameters
  def update_job_from_hash(params : Hash(String, String)) : Result
    results = [] of String
    job_id = params["job_id"]?
    return Result.error(HTTP::Status::BAD_REQUEST, "Error: Missing job_id") unless job_id

    job = get_job(job_id.to_i64)
    return Result.error(HTTP::Status::NOT_FOUND, "Error: Job not found") unless job

    # Prevent updates if the job is already in the "finish" stage
    if job.istage >= JOB_STAGE_NAME2ID["finish"] &&
       job.idata_readiness >= JOB_DATA_READINESS_NAME2ID["complete"]
      return Result.error(HTTP::Status::LOCKED, "Warning: Job closed, cannot update")
    end

    # Iterate over allowed parameters and update the job accordingly
    # job_state/job_health should be handled before job_stage, to record last_success_stage correctly
    %w(job_state job_health job_stage job_data_readiness job_step milestones renew_seconds ssh_port).each do |parameter|
      value = params[parameter]?
      next if value.nil? || value.empty?

      case parameter
      when "job_step"
        job.job_step = value
      when "job_state", "job_health", "job_stage", "job_data_readiness"
        result = update_job_state_or_stage(job, parameter, value)
        return result unless result.success
      when "milestones"
        update_milestones(job, value)
      when "renew_seconds"
        result = renew_job(job, value)
        results << result.message
        return result unless result.success
      when "ssh_port"
        job.hash_plain[parameter] = value unless value.empty?
      end
    end

    # Notify listeners about the job update
    send_job_event(job.id64, params.to_json)
    report_workflow_job_event(job.id64, job)

    Result.success(results.join("\n"))
  end

  # Helper method to update job state or stage
  def update_job_state_or_stage(job, parameter, value) : Result
    if JOB_DATA_READINESS_NAME2ID.has_key?(value)
      change_job_data_readiness(job, value)
    elsif JOB_STAGE_NAME2ID.has_key?(value)
      change_job_stage(job, value, nil)
    elsif JOB_HEALTH_NAME2ID.has_key?(value)
      change_job_stage(job, nil, value)
    else
      return Result.error(HTTP::Status::BAD_REQUEST, "Error: Unknown #{parameter}=#{value}")
    end

    Result.success("Updated #{parameter} to #{value}")
  end

  # Helper method to update milestones
  def update_milestones(job, value)
    values = value.split(/[ ,]+/)
    job.milestones ||= [] of String
    job.milestones += values
  end

  # API renew_seconds: extend job.renew_to_utc to (NOW+renew_seconds)
  # job.renew_to_utc: prevent terminate_timeout_jobs() killing job before this time
  def renew_job(job, value) : Result
    if job.job_stage == "submit"
      return Result.error(HTTP::Status::BAD_REQUEST, "Warning: Only running jobs can renew, your job stage is: #{job.job_stage}")
    end

    new_time = job.renew_addtime(value.to_i32)
    Result.success(new_time.to_s("%Y-%m-%dT%H:%M:%S%:z"))
  end

end
