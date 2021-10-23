# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./lib/json_logger"
require "monitoring/amqp"
require "monitoring/monitoring"
require "monitoring/constants"

module Monitoring
  log = JSONLogger.new
  message_queue_client = MessageQueueClient.new
  spawn message_queue_client.loop_monitoring_message_queue("docker-logging", "docker-logging", "docker")

  begin
    Kemal.run(MONITOR_PORT)
  rescue e
    log.error(e)
  end
end
