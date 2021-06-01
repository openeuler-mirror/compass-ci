# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def renew_deadline
    job_id = @env.params.query["job_id"]?.to_s
    time = @env.params.query["time"]?.to_s

    job = @es.get_job(job_id)
    raise "The job does not exist" if job.nil?

    check_renew_job(job)

    job.renew_deadline(time)
    @es.update_tbox(job["testbox"].to_s, {"deadline" => job["deadline"]})
    @es.set_job_content(job)

    @env.set "testbox", job["testbox"]
    @env.set "job_id", job["id"]
    @env.set "deadline", job["deadline"]
    send_mq_msg("renew")

    return true
  rescue e
    @env.response.status_code = 500
    @log.warn(e.inspect_with_backtrace)
    return false
  end

  def check_renew_job(job)
    raise "Only running job can be extended" unless job["job_state"] == "boot"

    testbox = @es.get_tbox(job["testbox"])
    raise "testbox that do not exist" if testbox.nil?
    raise "The testbox does not match the job" if job["id"] != testbox["job_id"]
  end
end
