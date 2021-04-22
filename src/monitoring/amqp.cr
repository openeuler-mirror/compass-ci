# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "amqp-client"

require "./monitoring"
require "./filter"
require "./constants"
require "../lib/json_logger"

class MessageQueueClient
  def initialize(host = MQ_HOST, port = MQ_PORT)
    @client = AMQP::Client.new("amqp://#{host}:#{port}")
    @log = JSONLogger.new
  end

  private def start
    conn = @client.connect
    yield conn
  ensure
    conn.try &.close
  end

  private def filter_msg(conn, filter, exchange_name, queue_name)
    conn.channel do |channel|
      queue = channel.queue(queue_name)
      queue.bind(exchange_name, "")
      queue.subscribe(tag: queue_name, block: true) do |msg|
        begin
          filter.filter_msg(msg.body_io)
        rescue e
          @log.warn({
            "resource" => "filter_message",
            "message" => e.inspect_with_backtrace,
            "data" => msg.body_io.to_s
          }.to_json)
        end
      end
    end
  end

  def monitoring_message_queue(filter : Filter, exchange_name : String, queue_name : String)
    loop do
      begin
        start do |conn|
          filter_msg(conn, filter, exchange_name, queue_name)
        end
      rescue e
        @log.warn({
          "resource" => "monitoring_message_queue",
          "message" => e.inspect_with_backtrace,
          "data" => "#{exchange_name}, #{queue_name}"
        }.to_json)
        sleep 5
      end
    end
  end
end
