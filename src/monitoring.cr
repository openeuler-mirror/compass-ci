# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./lib/json_logger"
require "monitoring/monitoring"
require "monitoring/constants"

module Monitoring
  log = JSONLogger.new

  begin
    Kemal.run(MONITOR_PORT)
  rescue e
    log.error(e)
  end
end
