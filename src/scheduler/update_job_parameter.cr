# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def api_update_job(env) : String
    job_id = env.params.query["job_id"]?
    raise "Error: no job_id" unless job_id

    job = get_job(job_id.to_i64)
    raise "Error: job not found" unless job

    env.set "job_id", job_id
    env.set "time", get_time

    # no need to update job
    raise "Warning: job finish, cannot update" if JOB_STAGE_NAME2ID[job.job_stage] >= JOB_STAGE_NAME2ID["finish"]

    # try to get report value and then update it
    delta_job = JobHash.new

    %w(job_state job_stage job_step milestones renew_seconds).each do |parameter|
      value = env.params.query[parameter]?
      next if value.nil? || value == ""

      env.set parameter, value

      case parameter
      when "job_step"
          job.job_step = value
          delta_job.job_step = value
      when "job_state", "job_stage"
        if JOB_STAGE_NAME2ID.has_key? value
          change_job_stage(job, value, nil)
          delta_job.job_stage = value
        elsif JOB_HEALTH_NAME2ID.has_key? value
          change_job_stage(job, "incomplete", value)
          delta_job.job_health = value
        else
          raise "Error: api_update_job: unknown #{parameter}=#{value}"
        end

        # job finished?
        if JOB_STAGE_NAME2ID[job.job_stage] >= JOB_STAGE_NAME2ID["finish"]
          on_job_close(job)
        end

      when "milestones"
        values = value.split(/[ ,]+/)
        if job.hash_array.has_key? "milestones"
          job.milestones += value.split(" ")
        else
          job.milestones = value.split(" ")
        end
        delta_job.milestones = job.milestones

      when "renew_seconds"
        raise "Warning: only running job can renew, your job stage is: #{job.job_stage}" if job.job_stage == "submit"
        job.renew_addtime(value.to_i32)
      end
    end

    delta_job.id = job_id
    update_id2job(delta_job)

    # json log
    log = delta_job.dup
    log.hash_plain["job_id"] = job_id
    log.hash_plain.delete("id")

    env.set "log", log.to_json
    send_mq_msg(env)

    # optimize away db updates except in on_finish_job()
    # @es.set_job(job)
    update_testbox_info(env, job)

    report_workflow_job_event(job_id.to_s, job)
    return "Success"
  rescue e
    env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
    return e.to_s
  end

  def update_testbox_info(env, job)
    testbox = job.testbox
    deadline = env.get?("deadline")

    hash = {"time" => env.get?("time").to_s}
    hash["deadline"] = deadline.to_s if deadline

    @es.update_tbox(testbox, hash)
  end

  def change_job_stage(job, job_stage, job_health)
    job.job_stage = job_stage
    job.set_time("#{job_stage}_time")

    if job_health
      job.job_health = job_health
    else
      job.last_success_stage = job_stage 
    end

    on_job_updated(job.id64)
  end

end
