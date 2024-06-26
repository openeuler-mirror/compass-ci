# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def update_job_parameter
    job_id = @env.params.query["job_id"]?
    return false unless job_id

    job = @es.get_job(job_id)
    return false unless job

    @env.set "job_id", job_id
    @env.set "time", get_time

    # the user actively returned this testbox
    # no need to update job
    return if job.job_health? == "return"

    # try to get report value and then update it
    delta_job = Job.new(Hash(String, JSON::Any).new, nil)

    (%w(start_time end_time loadavg job_state)).each do |parameter|
      value = @env.params.query[parameter]?
      next if value.nil? || value == ""

      if parameter == "start_time" || parameter == "end_time"
        value = Time.unix(value.to_i).to_local.to_s("%Y-%m-%dT%H:%M:%S+0800")
      end

      case parameter
      when "start_time"
        delta_job.start_time = value
      when "end_time"
        delta_job.end_time = value
      when "loadavg"
        delta_job.loadavg = value
      when "job_state"
        delta_job.job_state = value
      end
      next unless parameter == "job_state"

      if JOB_STAGES.includes?(value)
        delta_job.job_stage = value
        job.last_success_stage = value
        job.set_time("#{value}_time")
        job.set_boot_elapsed_time
        @env.set "job_stage", value
        @env.set "deadline", job.set_deadline(value).to_s
      else
        value = "success" if value == "finished"
        delta_job.job_health = value
      end
    end

    job.merge!(delta_job)
    delta_job.id = job_id

    update_id2job(delta_job)

    # json log
    log = delta_job.dup
    log.hash_plain["job_id"] = job_id
    log.hash_plain.delete("id")

    @env.set "log", log.to_json

    @es.set_job(job)
    update_testbox_info(job)

    report_workflow_job_event(job_id.to_s, job)
  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  ensure
    send_mq_msg
  end

  def update_testbox_info(job)
    testbox = job.testbox
    deadline = @env.get?("deadline")

    hash = {"time" => @env.get?("time").to_s}
    hash["deadline"] = deadline.to_s if deadline

    @es.update_tbox(testbox, hash)
  end
end
