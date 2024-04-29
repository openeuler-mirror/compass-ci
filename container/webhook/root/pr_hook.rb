#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'bunny'

host = ENV["MQ_HOST"] || '172.17.0.1'
port = ENV["MQ_PORT"] || 5672

connection = Bunny.new("amqp://#{host}:#{port}")
connection.start
channel = connection.create_channel

queue = channel.queue('openeuler-pr-webhook')
message = ARGV[0]
queue.publish(message)
connection.close
