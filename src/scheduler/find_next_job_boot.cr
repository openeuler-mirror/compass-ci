# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def find_next_job_boot
    hostname = @env.params.query["hostname"]?
    mac = @env.params.query["mac"]?
    if !hostname && mac
      hostname = @redis.hash_get("sched/mac2host", normalize_mac(mac))
    end

    response = get_job_boot(hostname, "ipxe")
    job_id = response[/tmpfs\/(.*)\/job\.cgz/, 1]?
    @log.info(%({"job_id": "#{job_id}", "job_state": "boot"})) if job_id

    response
  rescue e
    @log.warn(e)
  end
end
