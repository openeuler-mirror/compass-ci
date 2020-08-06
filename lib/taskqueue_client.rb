# frozen_string_literal: true

require 'rest-client'

# taskqueue client
class TaskQueueClient
  def initialize(host = '127.0.0.1', port = 3060)
    @host = host
    @port = port
  end

  def consume_task(queue_path)
    url = "http://#{@host}:#{@port}/consume?queue=#{queue_path}"
    RestClient::Request.execute(
      method: :put,
      url: url
    )
  end
end
