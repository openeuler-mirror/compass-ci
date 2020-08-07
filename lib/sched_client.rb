# frozen_string_literal: true

require 'rest-client'

# sched client class
class SchedClient
  HOST = (ENV.key?('SCHED_HOST') ? ENV['SCHED_HOST'] : '127.0.0.1')
  PORT = (ENV.key?('SCHED_PORT') ? ENV['SCHED_PORT'] : 3000).to_i
  def initialize(host = HOST, port = PORT)
    @host = host
    @port = port
  end

  def submit_job(job_json)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/submit_job")
    resource.post(job_json)
  end
end
