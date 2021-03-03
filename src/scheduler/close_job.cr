# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def close_job
    job_id = @env.params.query["job_id"]?
    return unless job_id

    @env.set "job_id", job_id

    job = @redis.get_job(job_id)

    # update job_state
    job_state = @env.params.query["job_state"]?
    job["job_state"] = job_state if job_state
    job["job_state"] = "complete" if job["job_state"] == "boot"

    response = @es.set_job_content(job)
    if response["_id"] == nil
      # es update fail, raise exception
      raise "es set job content fail!"
    end

    subqueue = job.subqueue
    queue = (subqueue == "idle" ? job.queue : "#{job.queue}/#{subqueue}")

    response = @task_queue.hand_over_task(
      "sched/#{queue}", "extract_stats", job_id
    )
    if response[0] != 201
      raise "#{response}"
    end

    @redis.remove_finished_job(job_id)

    job_state ||= "complete"
    @log.info(%({"job_id": "#{job_id}", "job_state": "#{job_state}"}))
  rescue e
    @log.warn(e)
  ensure
    source = @env.params.query["source"]?
    if source != "lifecycle"
      mq_msg = {
        "job_id" => @env.get?("job_id").to_s,
        "job_state" => "close",
        "time" => get_time
      }
      @mq.pushlish_confirm(JOB_MQ, mq_msg.to_json)
    end
  end
end
