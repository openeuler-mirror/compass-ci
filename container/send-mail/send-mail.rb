#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'mail'
require 'sinatra'

REDIS_HOST = %x(/sbin/ip route | awk '/default/ {print $3}').chomp
REDIS_PORT = ENV['REDIS_PORT']

require "#{ENV['CCI_SRC']}/lib/mail-post"

mail_server = %x(/sbin/ip route |awk '/default/ {print $3}').chomp

smtp = {
  address: mail_server,
  enable_starttls_auto: false
}

Mail.defaults { delivery_method :smtp, smtp }
