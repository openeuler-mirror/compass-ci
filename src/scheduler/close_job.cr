# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def close_job
    job_id = @env.params.query["job_id"]?
    return unless job_id

    @env.set "job_id", job_id
    @env.set "job_stage", "finish"

    job = nil
    begin
      job = get_id2job(job_id)
    rescue e
      @log.warn({
        "message" => e.to_s,
        "error_message" => e.inspect_with_backtrace.to_s
      }.to_json)
    end

    # whatever we should update job_state/stage/health
    # so we query job from es when can't find job from etcd
    job = @es.get_job(job_id) unless job
    raise "can't find job from etcd and es, job_id: #{job_id}" unless job

    # update job content
    job_state = @env.params.query["job_state"]?
    job["job_state"] = job_state if job_state
    job["job_state"] = "complete" if job["job_state"] == "boot"

    job["job_stage"] = "finish"

    job_health = @env.params.query["job_health"]?
    job["job_health"] = job["job_health"]? || job_health || "success"
    # if user returns this testbox
    # job_health needs to be return
    job["job_health"] = job_health if job_health == "return"


    job.set_time("close_time")
    @env.set "close_time", job["close_time"]

    if @env.params.query["source"]? != "lifecycle"
      deadline = job.get_deadline("finish")
      @env.set "deadline", deadline.to_s
      @es.update_tbox(job["testbox"].to_s, {"deadline" => deadline})
      job["last_success_stage"] = "finish"
    end

    if !job["in_watch_queue"].empty?
      data = {"job_id" => job["id"], "job_health" => job["job_health"]}
      @etcd.put_not_exists("watch_queue/#{job["in_watch_queue"]}/#{job["id"]}", data.to_json)
    end

    response = @es.set_job_content(job)
    if response["_id"] == nil
      # es update fail, raise exception
      raise "es set job content fail!"
    end
    "success"
  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
    e.to_s
  ensure
    send_mq_msg if @env.params.query["source"]? != "lifecycle"
    if job
      # need update the end job_health to etcd
      res = update_id2job(JSON.parse(job.dump_to_json))
      @log.info("scheduler update job to id2job #{job.id}: #{res}")
      res = move_process2stats(job)
      @log.info("scheduler move in_process to extract_stats #{job.id}: #{res}")
    end
  end
end
