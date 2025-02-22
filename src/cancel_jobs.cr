# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def cancel_jobs(env)
    body = env.request.body.not_nil!.gets_to_end

    content = JSON.parse(body)
    @accounts_cache.verify_account(content.as_h)

    job_ids = content["job_ids"]?
    query = content["query"]?
    raise "Missing required key: 'job_ids' or 'query''" unless (job_ids || query)

    job_ids = job_ids.as_a.map(&.as_i64) if job_ids
    results = cancel(query, job_ids, content["my_account"].to_s)

    { "results" => results }
  rescue e
    env.response.status_code = 202
    @log.warn(e)

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
    jobs = Hash(Int64, JobHash).new
    return jobs if jobs_ids
    return jobs unless query

    query = query.as_h
    query_jobs = @es.search("jobs", query, size=10000)
    query_jobs.each do |query|
      jobs[query["_id"].as_i64] = JobHash.new query["_source"].as_h
    end

    jobs
  end

  def get_job_ids(jobs, job_ids)
    return job_ids if job_ids

    jobs.keys
  end

  def cancel(query, job_ids, my_account)
    results = Array(Hash(String, String)).new
    update_jobs = Array(Hash(String, Hash(String, Int64 | JSON::Any | String))).new

    jobs = get_jobs(query, job_ids)
    job_ids = get_job_ids(jobs, job_ids)

    job_ids.each do |job_id|
      job = jobs[job_id]? || @es.get_job(job_id.to_s)
      result = check_one_job(job_id.to_s, job, my_account)
      results << result

      next unless result["result"] == "success"
      next unless job

      change_job_stage(job, "finish", "cancel")
      update_jobs << { "update" => { "index" => "jobs", "id" => job_id, "doc" => job.to_json_any}}
    rescue e
      @log.warn(e)

      results << {
        "result" => "failed",
        "job_id" => job_id.to_s,
        "message" => e.to_s
      }
    end
    spawn @es.bulk(update_jobs.to_json)
    results
  end

end
