# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require_relative './basic_env'

# detect task's status, return value:
# - "Manual deleted id=#{@task_id}"
# - "Alive too long id=#{@task_id}"
# - "Normal task id=#{@task_id}"
class AbnormalIdDetect
  def initialize(id, days = 3, content = nil)
    @task_id = id
    @day_number = days

    @content = get_taskqueue_content4id(content, id)
  end

  def check_alive_time_too_long(queue, rank, days)
    time = Time.now.to_f - days * 86_400 # 1 days = 24*60*60 seconds
    cmd = "#{CMD_BASE} queues/#{queue} , zrange #{rank} #{rank} withscores"
    result = `#{cmd}`.chomp

    # results[0]: task_id, member
    # results[1]: enqueue time, score
    results = result.split("\n")
    task_enqueue_time = results[1].to_f

    task_enqueue_time < time
  end

  def check
    return NO_DATA + "=#{@task_id}" if @content.nil?

    queue = @content['queue']

    # not found task_id at queue
    cmd = "#{CMD_BASE} queues/#{queue} , zrank #{@task_id}"
    result = `#{cmd}`.chomp
    return MANUAL_DELETED + "=#{@task_id}" if result.length.zero?

    # alive time large than special days
    result = check_alive_time_too_long(queue, result, @day_number)
    return ALIVE_TOO_LONG + "=#{@task_id}" if result

    "Normal task id=#{@task_id}"
  end

  def add_old_test_data(days_ago)
    queue = @content['queue']

    time = Time.now.to_f - days_ago * 86_400
    cmd = "#{CMD_BASE} queues/#{queue} , zadd #{time} #{@task_id}"
    `#{cmd}`.chomp
  end
end
