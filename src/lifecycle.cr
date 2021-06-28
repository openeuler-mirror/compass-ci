# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "lifecycle/lifecycle"
require "./lifecycle/constants"
require "./lib/json_logger"
require "./lib/lifecycle"

module Cycle
  log = JSONLogger.new
  lifecycle = Lifecycle.new

  # init @jobs and @machines
  # The cached data is corrected from the database every 10 minutes
  spawn lifecycle.init_from_es_loop

  lifecycle.mq_event_loop

  spawn lifecycle.timeout_job_loop
  spawn lifecycle.timeout_machine_loop

  Kemal.run(LIFECYCLE_PORT)
end
