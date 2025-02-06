# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def renew_deadline(env)
    job_id = env.params.query["job_id"]?.to_s
    time = env.params.query["time"]?.to_s

    job = @es.get_job(job_id)
    raise "The job does not exist" if job.nil?

    check_renew_job(job)

    job.renew_deadline(time)
    @es.update_tbox(job.testbox, {"deadline" => job.deadline})
    @es.set_job(job)

    env.set "testbox", job.testbox
    env.set "job_id", job.id
    env.set "deadline", job.deadline
    env.set "job_stage", "renew"
    send_mq_msg(env)

    return job.deadline
  rescue e
    env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
    return e.to_s
  end

  def check_renew_job(job)
    non_running = ["submit", "finish"]
    raise "Only running job can renew, your job stage is: #{job.job_stage}" if non_running.includes?(job.job_stage)

    testbox = @es.get_tbox(job.testbox)
    raise "testbox that do not exist" if testbox.nil?
    raise "The testbox does not match the job" if job.id != testbox["job_id"]
  end

  def get_deadline(env)
    testbox = env.params.query["testbox"]?.to_s
    testbox_info = @es.get_tbox(testbox)
    raise "cant find the testbox in es, testbox: #{testbox}" unless testbox_info

    deadline = testbox_info["deadline"] == nil ? "no deadline" : testbox_info["deadline"].to_s

    return deadline
  rescue e
    env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)

    return e.to_s
  end
end
