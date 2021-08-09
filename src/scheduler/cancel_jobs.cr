# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def cancel_jobs
    results = Array(Hash(String, String)).new
    body = @env.request.body.not_nil!.gets_to_end

    content = JSON.parse(body)
    raise "Missing required key: 'my_email'" unless content["my_email"]?

    account_info = @es.get_account(content["my_email"].to_s)
    Utils.check_account_info(content, account_info)

    job_ids = content["job_ids"]?
    raise "Missing required key: 'job_ids'" unless job_ids

    job_ids.as_a.uniq!.each do |job_id|
      res = cancel_job(content["my_account"], job_id.to_s)
      @log.info(res.to_json)
      results << res
    end

    { "results" => results }
  rescue e
    @env.response.status_code = 202
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)

    { "error_msg" => e.to_s }
  end

  def cancel_job(my_account, job_id)
    response = {
      "result" => "success",
      "job_id" => job_id,
      "message" => ""
    }

    job = @es.get_job(job_id.to_s)
    unless job
      response["result"] = "failed"
      response["message"] = "can't find job from es"
      return response
    end

    if my_account != job["my_account"]
      response["result"] = "forbidden"
      response["message"] = "can only cancel the job submitted by yourself"
      return response
    end

    return response if job["job_health"] == "cancel"

    if job["job_stage"] != "submit"
      response["result"] = "unsupported"
      response["message"] = "only jobs whose job_stage is submit can be cancelled"
      return response
    end

    delete_job_from_ready_queue(job)
    job["job_health"] = "cancel"
    @es.update_job(job)
    response
  rescue e
    @log.warn({
      "job_id" => job_id,
      "job_state" => "cancel",
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    })

    {
      "result" => "failed",
      "job_id" => job_id,
      "message" => e.to_s
    }
  end

  def delete_job_from_ready_queue(job)
    res = @etcd.delete("sched/ready/#{job.queue}/#{job.subqueue}/#{job.id}")
    @etcd.delete("sched/id2job/#{job.id}") if res.deleted == 1
  end
end
