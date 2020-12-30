require "kemal"
require "json"

require "./filter"
require "./amqp"

module Monitoring
  filter = Filter.new

  message_queue_client = MessageQueueClient.new

  spawn message_queue_client.monitoring_message_queue(filter, "serial-logging", "serial-logging")
  spawn message_queue_client.monitoring_message_queue(filter, "docker-logging", "docker-logging")

  ws "/filter" do |socket|
    query = JSON::Any.new("")

    socket.on_message do |msg|
      # query like {"job_id": "1"}
      # also can be {"job_id": ["1", "2"]}
      query = JSON.parse(msg)
      if query.as_h?
        query = filter.add_filter_rule(query, socket)
      end
    end

    socket.on_close do
      next unless query.as_h?

      filter.remove_filter_rule(query, socket)
    end
  end
end
