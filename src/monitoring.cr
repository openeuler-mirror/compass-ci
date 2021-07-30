# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./lib/json_logger"
require "monitoring/monitoring"
require "monitoring/filter"
require "monitoring/constants"

module Monitoring
  log = JSONLogger.new
  filter = Filter.instance
  message_queue_client = MessageQueueClient.new
  spawn message_queue_client.monitoring_message_queue(filter, "serial-logging", "serial-logging")
  spawn message_queue_client.monitoring_message_queue(filter, "docker-logging", "docker-logging")

  begin
    Kemal.run(MONITOR_PORT)
  rescue e
    log.error(e)
  end
end
