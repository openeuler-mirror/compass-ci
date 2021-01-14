# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'

require_relative './constants'
require_relative '../../lib/taskqueue_client'

# consume assister task queue
class Delimiter
  def initialize
    @tq = TaskQueueClient.new
  end

  def start_delimit
    loop do
      begin
        # consume delimiter task queue
        task = consume_delimiter_queue
        unless task
          sleep(60)
          next
        end

        %x(#{LKP_SRC}/sbin/submit bad_job_id=#{task['job_id']} error_id=#{task['error_id'].inspect} bisect.yaml queue='dc-bisect')
      rescue StandardError => e
        puts e
        sleep(60)
      end
    end
  end

  private

  def consume_delimiter_queue
    response = @tq.consume_task(DELIMITER_TASK_QUEUE)
    return unless response.code == 200

    body = JSON.parse(response.body).to_hash
    return body
  end
end
