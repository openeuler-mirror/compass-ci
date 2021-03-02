# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "singleton"
require "amqp-client"

class MQClient
  getter ch : AMQP::Client::Channel
  MQ_HOST = ENV.has_key?("MQ_HOST") ? ENV["MQ_HOST"] : "172.17.0.1"
  MQ_PORT = (ENV.has_key?("MQ_PORT") ? ENV["MQ_PORT"] : 5672).to_i32

  def initialize(host = MQ_HOST, port = MQ_PORT)
    @client = AMQP::Client.new("amqp://#{host}:#{port}")
    conn = @client.connect
    @ch = conn.channel.as(AMQP::Client::Channel)
  end

  def self.instance
    Singleton::Of(self).instance
  end

  def pushlish_confirm(queue, msg)
    q = @ch.queue(queue)
    q.publish_confirm msg
  end

  def pushlish(queue, msg)
    q = @ch.queue(queue)
    q.publish msg
  end

  def get(queue)
    q = @ch.queue(queue)
    q.subscribe(no_ack: false) do |msg|
      @ch.basic_ack(msg.delivery_tag)
      msg.body_io.to_s
    end
  end
end
