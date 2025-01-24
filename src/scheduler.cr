# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./scheduler/scheduler"
require "./scheduler/constants.cr"
require "./lib/json_logger"
require "./lib/do_local_pack"
require "./lib/create_secrets_yaml"
require "./lib/queue"
require "./lib/subqueue"
require "./lib/init_ready_queues"

module Scheduler
  log = JSONLogger.new

  begin
    create_secrets_yaml("scheduler")
    do_local_pack
    spawn Queue.instance.timing_refresh_from_etcd
    spawn Subqueue.instance.timing_refresh_from_es
    spawn InitReadyQueues.instance.loop_init
    Kemal.run(ENV["NODE_PORT"].to_i32)
  rescue e
    log.error(e)
  end
end
