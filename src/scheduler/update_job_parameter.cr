# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def update_job_parameter
    job_id = @env.params.query["job_id"]?
    if !job_id
      return false
    end

    @env.set "job_id", job_id
    @env.set "time", get_time

    # try to get report value and then update it
    job_content = {} of String => String
    job_content["id"] = job_id

    (%w(start_time end_time loadavg job_state)).each do |parameter|
      value = @env.params.query[parameter]?
      if !value || value == ""
        next
      end
      if parameter == "start_time" || parameter == "end_time"
        value = Time.unix(value.to_i).to_local.to_s("%Y-%m-%d %H:%M:%S")
      end

      job_content[parameter] = value
    end

    @redis.update_job(job_content)

    # json log
    log = job_content.dup
    log["job_id"] = log.delete("id").not_nil!
    @log.info(log.to_json)

    @env.set "job_state", job_content["job_state"]?
    update_testbox_time(job_id)
  rescue e
    @log.warn(e)
  ensure
    mq_msg = {
      "job_id" => @env.get?("job_id").to_s,
      "job_state" => (@env.get?("job_state") || "update").to_s,
      "time" => @env.get?("time").to_s
    }
    @mq.pushlish_confirm(JOB_MQ, mq_msg.to_json)
  end
end
