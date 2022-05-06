# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'bunny'

class MQClient
  # How to use:
  # MQClient.new(:hostname => mq_host, :port => mq_port, :automatically_recover => false)
  def initialize(opts = {})
    opts[:hostname] = 'localhost' unless opts[:hostname]
    opts[:port] = '5672' unless opts[:port]
    @conn = Bunny.new(opts)
    @conn.start
    @channel = @conn.create_channel
  end

  def fanout_queue(exchange_name, queue_name)
    x = @channel.fanout(exchange_name)
    @channel.queue(queue_name).bind(x)
  end

  def fanout(exchange_name)
    @channel.fanout(exchange_name)
  end

  def queue(queue_name, opts = {})
    @channel.queue(queue_name, opts)
  end

  def ack(delivery_info)
    @channel.ack(delivery_info.delivery_tag)
  end
end
