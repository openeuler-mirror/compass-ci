# SPDX-License-Identifier: MulanPSL-2.0+

require "scheduler/scheduler"
require "./scheduler/constants.cr"

module Scheduler
  Kemal.run(SCHED_PORT)
end
