# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "http/client"

# scheduler API class
class SchedulerAPI
  def initialize
    @port = ENV.has_key?("SCHED_PORT") ? ENV["SCHED_PORT"].to_i32 : 3000
    @host = ENV.has_key?("SCHED_HOST") ? ENV["SCHED_HOST"] : "172.17.0.1"
  end

  def close_job(job_id)
    client = HTTP::Client.new(@host, port: @port)
    response = client.get("/~lkp/cgi-bin/lkp-post-run?job_id=#{job_id}")
    client.close()
    return response
  end
end
