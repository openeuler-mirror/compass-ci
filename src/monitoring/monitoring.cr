require "kemal"
require "json"

require "./filter"
require "./amqp"

module Monitoring
  filter = Filter.new

  message_queue_client = MessageQueueClient.new

  spawn message_queue_client.monitoring_message_queue(filter, "logging-test", "logging-test")

  ws "/filter" do |socket|
    query = JSON::Any.new("")

    socket.on_message do |msg|
      # query like {"job_id": 1}
      query = JSON.parse(msg)
      if query.as_h?
        filter.add_filter_rule(query, socket)
      end
    end

    socket.on_close do
      next unless query.as_h?

      filter.remove_filter_rule(query, socket)
    end
  end
end
