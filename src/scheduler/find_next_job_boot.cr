# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def find_next_job_boot
    hostname = @env.params.query["hostname"]?
    mac = @env.params.query["mac"]?
    if !hostname && mac
      hostname = @redis.hash_get("sched/mac2host", normalize_mac(mac))
    end
    if !hostname
      raise "cannot find hostname"
    end

    pre_job_id = @env.params.query["pre_job_id"]?
    pre_job = @es.get_job(pre_job_id.to_s)

    @env.set "testbox", hostname

    response = get_job_boot(hostname, "ipxe", pre_job)
    job_id = response[/tmpfs\/(.*)\/job\.cgz/, 1]?

    @env.set "job_id", job_id

    response
  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  ensure
    send_mq_msg
  end
end
