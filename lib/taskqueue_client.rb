# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'rest-client'

# taskqueue client
class TaskQueueClient
  HOST = (ENV.key?('TASKQUEUE_HOST') ? ENV['TASKQUEUE_HOST'] : '172.17.0.1')
  PORT = (ENV.key?('TASKQUEUE_PORT') ? ENV['TASKQUEUE_PORT'] : 3060).to_i
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

  def add_task(queue_path, json_data)
    url = "http://#{@host}:#{@port}/add?queue=#{queue_path}"
    RestClient::Request.execute(
      method: :post,
      url: url,
      payload: json_data,
      headers: { content_type: 'application/json' }
    )
  end
end
