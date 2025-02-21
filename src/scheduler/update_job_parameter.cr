# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def api_update_job(env : HTTP::Server::Context) : String
    job_id = env.params.query["job_id"]?
    raise "Error: no job_id" unless job_id

    job = get_job(job_id.to_i64)
    raise "Error: job not found" unless job

    # no need to update job
    raise "Warning: job finish, cannot update" if JOB_STAGE_NAME2ID[job.job_stage] >= JOB_STAGE_NAME2ID["finish"]

    %w(job_state job_stage job_step milestones renew_seconds).each do |parameter|
      value = env.params.query[parameter]?
      next if value.nil? || value == ""

      case parameter
      when "job_step"
          job.job_step = value

      when "job_state", "job_stage", "job_data_readiness"
        if JOB_DATA_READINESS_NAME2ID.has_key? value
          change_job_data_readiness(job, value)
        elsif JOB_STAGE_NAME2ID.has_key? value
          change_job_stage(job, value, nil)
        elsif JOB_HEALTH_NAME2ID.has_key? value
          change_job_stage(job, "finish", value)
        else
          raise "Error: api_update_job: unknown #{parameter}=#{value}"
        end

      when "milestones"
        values = value.split(/[ ,]+/)
        if job.hash_array.has_key? "milestones"
          job.milestones += value.split(" ")
        else
          job.milestones = value.split(" ")
        end

      when "renew_seconds"
        raise "Warning: only running job can renew, your job stage is: #{job.job_stage}" if job.job_stage == "submit"
        job.renew_addtime(value.to_i32)
      end
    end

    # optimize away db updates except in on_finish_job()
    # @es.update_doc("jobs", ...)

    report_workflow_job_event(job_id.to_s, job)
    return "Success"
  rescue e
    env.response.status_code = 500
    @log.warn(e)
    return e.to_s
  end

end
