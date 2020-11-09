# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def close_job(job_id : String)
    job = @redis.get_job(job_id)

    delete_access_key_file(job) if job

    response = @es.set_job_content(job)
    if response["_id"] == nil
      # es update fail, raise exception
      raise "es set job content fail!"
    end

    response = @task_queue.hand_over_task(
      "sched/#{job.queue}", "extract_stats", job_id
    )
    if response[0] != 201
      raise "#{response}"
    end

    @redis.remove_finished_job(job_id)

    return %({"job_id": "#{job_id}", "job_state": "complete"})
  end

  def delete_access_key_file(job : Job)
    File.delete(job.access_key_file) if File.exists?(job.access_key_file)
  end
end
