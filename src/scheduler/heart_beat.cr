# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
#
class Sched
  def heart_beat(env)
    # hostname = k8s-at1
    type = env.params.query["type"]
    hostname = env.params.query["hostname"]
    is_remote = env.params.query["is_remote"]

    _hostname = "local-#{hostname}"
    _hostname = "remote-#{hostname}" if is_remote == "true"

    if TBOX_TYPES.includes?(type)
      key = "/tbox/#{type}/#{_hostname}"
      val = @redis.get(key)
      @log.info("please retry register, hostname: #{hostname}") if val.nil?
      return 1001 if val.nil?

      @redis.expire(key, 60)
    end
    return 1000
  end
end

