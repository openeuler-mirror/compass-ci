# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def api_set_job_stage(env)
    job_id, job_stage, timeout = get_params_info(env)

    job = @es.get_job(job_id.to_s)
    raise "can't faind this job in es: #{job_id}" unless job

    # the user actively returned this testbox
    # no need to update job
    return if job.job_health == "return"

    env.set "time", get_time

    change_job_stage(job, job_stage)
    env.set "deadline", job.set_deadline(job_stage, timeout.to_i32).to_s
    update_database(job)

    report_workflow_job_event(job_id.to_s, job)

  rescue e
    env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  ensure
    send_mq_msg(env)
  end

  def update_database(job)
    update_id2job(job)
    @es.set_job(job)
    update_testbox_info(job)
  end

  def change_job_stage(job, job_stage)
    job.job_stage = job_stage
    job.last_success_stage = job_stage
    job.set_time("#{job_stage}_time")
  end

  def get_params_info(env)
    job_id = env.params.query["job_id"]?.to_s
    job_stage = env.params.query["job_stage"]?.to_s
    timeout = env.params.query["timeout"]?.to_s || 0.to_s

    env.set "job_id", job_id
    env.set "job_stage", job_stage

    check_params({"job_id" => job_id, "job_stage" => job_stage})
    [job_id, job_stage, timeout]
  end

  def check_params(hash)
    missing_params = Array(String).new
    hash.each do |k, v|
      missing_params << k if v.to_s.empty?
    end
    return if missing_params.empty?

    raise "param error: missing #{missing_params}"
  end
end
