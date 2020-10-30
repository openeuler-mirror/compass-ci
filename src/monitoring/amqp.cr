require "amqp-client"

require "./monitoring"
require "./filter"
require "./constants"

class MessageQueueClient
  def initialize(host = MQ_HOST, port = MQ_PORT)
    @client = AMQP::Client.new("amqp://#{host}:#{port}")
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
          puts "filter message error: #{e}"
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
        puts "monitoring_message_queue error: #{e}"
        sleep 5
      end
    end
  end
end
