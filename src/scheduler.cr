# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "scheduler/scheduler"
require "./scheduler/constants.cr"

module Scheduler
  Kemal.run(SCHED_PORT)
end
