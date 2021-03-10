# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require "bunny"

class MQClient
  def initialize(hostname = "localhost", port = "5672")
    @conn = Bunny.new(hostname: hostname, port: port)
    @conn.start
    @channel = @conn.create_channel
  end

  def queue(queue_name, opts = {})
    @channel.queue(queue_name, opts)
  end

  def ack(delivery_info)
    @channel.ack(delivery_info.delivery_tag)
  end
end
