# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def cancel_jobs
    body = @env.request.body.not_nil!.gets_to_end

    content = JSON.parse(body)
    raise "Missing required key: 'my_email'" unless content["my_email"]?

    account_info = @es.get_account(content["my_email"].to_s)
    Utils.check_account_info(content, account_info)

    job_ids = content["job_ids"]?
    query = content["query"]?
    raise "Missing required key: 'job_ids' or 'query''" unless (job_ids || query)

    results = cancel(query, job_ids, account_info["my_account"].to_s)

    { "results" => results }
  rescue e
    @env.response.status_code = 202
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)

    { "error_msg" => e.to_s }
  end

  def check_one_job(job_id, job, my_account)
    response = {
      "result" => "success",
      "job_id" => job_id,
      "message" => ""
    }

    unless job
      response["result"] = "failed"
      response["message"] = "can't find job from es"
      return response
    end

    if my_account != job.my_account
      response["result"] = "forbidden"
      response["message"] = "can only cancel the job submitted by yourself"
      return response
    end

    if job.job_stage != "submit"
      response["result"] = "unsupported"
      response["message"] = "only jobs whose job_stage is submit can be cancelled"
      return response
    end

    response
  end

  def get_jobs(query, jobs_ids)
    jobs = Hash(String, JobHash).new
    return jobs if jobs_ids
    return jobs unless query

    query = query.as_h
    _source = ["my_account", "queue", "subqueue", "job_stage"]
    query_jobs = @es.search_by_fields("jobs", query, size=10000, source=_source)
    query_jobs.each do |query|
      jobs[query["_id"].as_s] = JobHash.new query["_source"].as_h
    end

    jobs
  end

  def get_job_ids(jobs, job_ids)
    return job_ids.as_a if job_ids

    jobs.keys
  end

  def cancel(query, job_ids, my_account)
    results = Array(Hash(String, String)).new
    update_jobs = Array(Hash(String, Hash(String, Hash(String, String) | String))).new

    jobs = get_jobs(query, job_ids)
    job_ids = get_job_ids(jobs, job_ids)

    job_ids.each do |job_id|
      job = jobs[job_id]? || @es.get_job(job_id.to_s)
      result = check_one_job(job_id.to_s, job, my_account)
      results << result

      next unless result["result"] == "success"
      next unless job

      delete_job_from_submit_queue(job_id)
      update_jobs << { "update" => { "_id" => job_id.to_s, "data" => { "job_health" => "cancel"}}}
    rescue e
      @log.warn({
        "job_id" => job_id,
        "job_state" => "cancel",
        "message" => e.to_s,
        "error_message" => e.inspect_with_backtrace.to_s
      })

      results << {
        "result" => "failed",
        "job_id" => job_id.to_s,
        "message" => e.to_s
      }
    end
    spawn @es.bulk(update_jobs, index="jobs")
    results
  end

  def delete_job_from_submit_queue(job_id)
    res = @etcd.delete("/queues/sched/submit/dc-custom/#{job_id}")
    @etcd.delete("queues/sched/id2job/#{job_id}") if res.deleted == 1
  end

  def delete_job_from_ready_queue(queue, subqueue, job_id)
    res = @etcd.delete("/queues/sched/ready/#{queue}/#{subqueue}/#{job_id}")
    @etcd.delete("queues/sched/id2job/#{job_id}") if res.deleted == 1
  end
end
