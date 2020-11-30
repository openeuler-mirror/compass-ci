# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def update_job_parameter
    job_id = @env.params.query["job_id"]?
    if !job_id
      return false
    end

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
    return log.to_json
  end
end
