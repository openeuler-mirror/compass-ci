# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "amqp-client"

require "./monitoring"
require "./filter"
require "./constants"
require "./parse_serial_logs"
require "../lib/json_logger"

class MessageQueueClient
  def initialize(host = MQ_HOST, port = MQ_PORT)
    @client = AMQP::Client.new("amqp://#{host}:#{port}")
    @log = JSONLogger.new
    @filter = Filter.instance
    @sp = SerialParser.new
  end

  private def start
    conn = @client.connect
    yield conn
  ensure
    conn.try &.close
  end

  private def deal_msg(msg, type)
    msg = JSON.parse(msg.to_s).as_h?
    return unless msg

    case type
    when "docker"
      @filter.filter_msg(msg)
    when "serial"
      @sp.deal_serial_log(msg)
    else
      @log.warn("deal msg unknow type: #{type}")
    end
  rescue e
    @log.warn({
      "resource" => "deal_msg",
      "message" => e.inspect_with_backtrace,
      "data" => msg.to_s
    }.to_json)
  end

  private def subscribe_msg(conn, exchange_name, queue_name, type)
    conn.channel do |channel|
      count = 1
      queue = channel.queue(queue_name)
      queue.bind(exchange_name, "")

      queue.subscribe(tag: queue_name, block: true) do |msg|
        count += 1
        (count = 1; Fiber.yield) if count & 0xFF == 0
        deal_msg(msg.body_io, type)
      end
    end
  end

  def loop_monitoring_message_queue(exchange_name : String, queue_name : String, type = "docker")
    loop do
      start do |conn|
        subscribe_msg(conn, exchange_name, queue_name, type)
      end
    rescue e
      @log.warn({
        "resource" => "monitoring_message_queue",
        "message" => e.inspect_with_backtrace,
        "data" => "#{exchange_name}, #{queue_name}"
      }.to_json)
      sleep 5.seconds
    end
  end
end
