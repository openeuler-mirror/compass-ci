# SPDX-License-Identifier: MulanPSL-2.0+

require "./taskqueue/taskqueue"

taskqueue = TaskQueue.new
taskqueue.run
