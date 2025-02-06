# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "http/client"

# scheduler API class
class SchedulerAPI
  def initialize
    @port = ENV.has_key?("SCHED_PORT") ? ENV["SCHED_PORT"].to_i32 : 3000
    @host = ENV.has_key?("SCHED_HOST") ? ENV["SCHED_HOST"] : "172.17.0.1"
  end

  def close_job(job_id, job_state = nil, source = nil, job_health = nil)
    url = "/scheduler/lkp/post-run?job_id=#{job_id}&source=#{source}"
    url += "&job_state=#{job_state}" if job_state
    url += "&job_health=#{job_health}" if job_health
    client = HTTP::Client.new(@host, port: @port)
    response = client.get(url)
    client.close
    return response
  end
end
