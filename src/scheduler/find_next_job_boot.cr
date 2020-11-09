# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def find_next_job_boot(env)
    hostname = env.params.query["hostname"]?
    mac = env.params.query["mac"]?
    if !hostname && mac
      hostname = @redis.hash_get("sched/mac2host", normalize_mac(mac))
    end

    get_job_boot(hostname, "ipxe")
  end
end
