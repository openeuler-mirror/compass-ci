#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'rufus-scheduler'
require 'redis'

redis = Redis.new(host: REDIS_HOST, port: REDIS_PORT)
email_init = Rufus::Scheduler.new

# Timing work for email counting everyday.
# the email counts queues will be reset everyday
# to ensure can send mail in the new day to user.
email_init.cron '0 0 * * *' do
  redis.del 'email_in_limit'
  redis.del 'email_out_limit'
end
