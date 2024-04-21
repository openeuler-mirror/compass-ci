# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def submit_job
    response = [] of Hash(String, String)
    body = @env.request.body.not_nil!.gets_to_end

    job_content = JSON.parse(body)
    origin_job = init_job(job_content)
    #if has upload_field, return it and notify client resubmit
    upload_fields = origin_job.process_user_files_upload
    if upload_fields
      return [{
        "message" => "#{upload_fields}",
        "errcode" => "RETRY_UPLOAD",
      }]
    end
    jobs = @env.cluster.handle_job(origin_job)
    jobs.each do |job|
      job.delete_account_info
      init_job_id(job)
      @env.pkgbuild.handle_job(job)
      @env.finally.handle_job(job)

      response << {
        "job_id"      => job.id,
        "message"     => "",
        "job_state"   => "submit",
        "result_root" => "/srv#{job.result_root}",
      }
    end

    return response
  rescue e
    @env.response.status_code = 202
    @log.warn({
      "message"       => e.to_s,
      "job_content"   => public_content(job_content),
      "error_message" => e.inspect_with_backtrace.to_s,
    }.to_json)

    response = [{
      "job_id"    => "0",
      "message"   => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s,
      "job_state" => "submit",
    }]
  ensure
    response.each do |job_message|
      @log.info(job_message.to_json)
    end
  end

  def public_content(job_content)
    return "" unless job_content

    temp = job_content.as_h
    fields = ["my_email", "my_token", "my_ssh_pubkey", "secrets", "pkg_data"]
    fields.each do |field|
      temp.delete(field) if temp.has_key?(field)
    end

    return temp.to_json
  end

  def init_job(job_content)
    job_hash = job_content.as_h
    fields = ["id", "plugins"]
    fields.each do |field|
      job_hash.delete(field)
    end

    job = Job.new(job_hash, nil)
    job.submit
    set_commit_date(job)

    return job
  end

  def init_job_id(job)
    id = job.id == "-1" ? @redis.get_job_id(job.lab) : job.id
    save_secrets(job, id)
    job.update_id(id)
  end

  def add_job2es(job)
    response = @es.set_job_content(job)
    msg = (response["error"]? ? response["error"]["root_cause"] : "")
    raise msg.to_s if response["error"]?
  end

  def set_commit_date(job)
    return if job["upstream_repo"] == "" || job["upstream_commit"] == ""

    data = JSON.parse(%({"git_repo": "#{job["upstream_repo"]}.git",
                   "git_command": ["git-log", "--pretty=format:%cd", "--date=unix",
                   "#{job["upstream_commit"]}", "-1"]}))
    response = @rgc.git_command(data)
    job["commit_date"] = response.body if response.status_code == 200
  end

  def save_secrets(job, job_id)
    return nil unless job["secrets"]?

    @redis.hash_set("id2secrets", job_id, job["secrets"]?.to_json)
    job.delete("secrets")
  end
end
