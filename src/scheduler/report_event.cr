# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def report_event(env)
    body = env.request.body
    env.set "log", body.to_s
  rescue e
    env.response.status_code = 500
    @log.warn(e)
  end
end
