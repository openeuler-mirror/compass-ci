# frozen_string_literal: true

require 'rest-client'

# taskqueue client
class TaskQueueClient
  HOST = (ENV.key?('TASK_QUEUE_HOST') ? ENV['TASK_QUEUE_HOST'] : '127.0.0.1')
  PORT = (ENV.key?('TASK_QUEUE_PORT') ? ENV['TASK_QUEUE_PORT'] : 3060).to_i
  def initialize(host = HOST, port = PORT)
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
