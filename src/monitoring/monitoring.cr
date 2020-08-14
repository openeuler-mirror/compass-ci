require "kemal"
require "json"

require "./filter"

module Monitoring
  filter = Filter.new

  ws "/filter" do |socket|
    query = JSON::Any.new("")

    socket.on_message do |msg|
      socket.send "query=>#{msg}"
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
