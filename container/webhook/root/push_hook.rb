#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'bunny'

connection = Bunny.new('amqp://172.17.0.1:5672')
connection.start
channel = connection.create_channel

queue = channel.queue('web_hook')
message = ARGV[0]
queue.publish(message)
connection.close
