# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "lifecycle/lifecycle"
require "./lifecycle/constants.cr"
require "./lib/json_logger"

module Cycle
  log = JSONLogger.new

  begin
    Kemal.run(LIFECYCLE_PORT)
  rescue e
    log.error(e)
  end
end
