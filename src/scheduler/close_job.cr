# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def close_job
    job_id = @env.params.query["job_id"]?
    return unless job_id

    job = @redis.get_job(job_id)

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

    @log.info(%({"job_id": "#{job_id}", "job_state": "complete"}))
  rescue e
    @log.warn(e)
  end
end
