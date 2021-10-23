# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "monitoring/amqp"
require "monitoring/constants"

module SerialLogging
  message_queue_client = MessageQueueClient.new
  message_queue_client.loop_monitoring_message_queue("serial-logging", "serial-logging", "serial")
end
