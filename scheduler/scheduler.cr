require "scheduler/scheduler"
require "./scheduler/constants.cr"

module Scheduler
    Kemal.run(SCHED_PORT)
end
