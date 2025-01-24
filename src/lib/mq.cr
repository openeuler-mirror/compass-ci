# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "singleton"
require "amqp-client"
require "amq-protocol"

require "./json_logger"

class MQClient
  getter ch : AMQP::Client::Channel
  MQ_HOST = ENV.has_key?("MQ_HOST") ? ENV["MQ_HOST"] : "172.17.0.1"
  MQ_PORT = (ENV.has_key?("MQ_PORT") ? ENV["MQ_PORT"] : 5672).to_i32

  def initialize(host = MQ_HOST, port = MQ_PORT)
    @log = JSONLogger.new
    @client = AMQP::Client.new("amqp://#{host}:#{port}")
    conn = @client.connect
    @ch = conn.channel.as(AMQP::Client::Channel)
  end

  def reconnect
    conn = @client.connect
    @ch = conn.channel.as(AMQP::Client::Channel)
    @log.info({
      "msg" => "rabbitmq reconnected successfully",
      "source" => "mq_client"
    }.to_json)
  rescue e
    @log.warn({
      "msg" => e.inspect_with_backtrace,
      "source" => "mq_client"
    }.to_json)
  end

  def self.instance
    Singleton::Of(self).instance
  end

  def publish_confirm(queue, msg, passive = false, durable = false, exclusive = false, auto_delete = false)
    q = @ch.queue(queue, passive, durable, exclusive, auto_delete)
    if durable
      q.publish_confirm(msg, props: AMQ::Protocol::Properties.new(delivery_mode: 2))
    else
      q.publish_confirm msg
    end
  end

  def retry_publish_confirm(queue, msg, passive = false, durable = false, exclusive = false, auto_delete = false)
    10.times do |i|
      publish_confirm(queue, msg, passive, durable, exclusive, auto_delete)
      break
    rescue e
      if i == 9
        @log.warn({
          "msg" => e,
          "error_msg" => e.inspect_with_backtrace,
          "source" => "retry_publish_confirm"
        })
        return
      else
        @log.info("publish confirm failed: #{e}")
        sleep (10 * i * i).seconds
        reconnect
      end
    end
  end

  def publish(queue, msg, passive = false, durable = false, exclusive = false, auto_delete = false)
    q = @ch.queue(queue, passive, durable, exclusive, auto_delete)
    if durable
      q.publish(msg, props: AMQ::Protocol::Properties.new(delivery_mode: 2))
    else
      q.publish(msg)
    end
  end

  def get(queue)
    q = @ch.queue(queue)
    q.subscribe(no_ack: false) do |msg|
      @ch.basic_ack(msg.delivery_tag)
      msg.body_io.to_s
    end
  end
end
