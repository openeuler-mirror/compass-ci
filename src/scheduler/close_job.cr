# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def close_job
    job_id = @env.params.query["job_id"]?
    return unless job_id

    @env.set "job_id", job_id
    @env.set "job_stage", "finish"

    job = get_id2job(job_id)

    # update job_state
    job_state = @env.params.query["job_state"]?
    job["job_state"] = job_state if job_state
    job["job_state"] = "complete" if job["job_state"] == "boot"

    job["job_stage"] = "finish"
    job_health = @env.params.query["job_health"]?
    job_health ||= job["job_health"]? || "success"
    job["job_health"] = job_health

    job.set_time("close_time")
    @env.set "close_time", job["close_time"]

    deadline = job.get_deadline("finish")
    @env.set "deadline", deadline
    @es.update_tbox(job["testbox"].to_s, {"deadline" => deadline})

    response = @es.set_job_content(job)
    if response["_id"] == nil
      # es update fail, raise exception
      raise "es set job content fail!"
    end

    move_process2stats(job)
    delete_id2job(job.id)
  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  ensure
    send_mq_msg if @env.params.query["source"]? != "lifecycle"
  end
end
