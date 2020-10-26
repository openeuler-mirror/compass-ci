#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'mail'
require 'sinatra'

require "#{ENV['CCI_SRC']}/lib/mail-post"

smtp = {
  address: 'smtp.qq.com',
  port: 25,
  domain: 'qq.com',
  user_name: ENV['ROBOT_EMAIL_ADDRESS'],
  password: ENV['ROBOT_EMAIL_PASSWORD'],
  openssl_verify_mode: 'none',
  enable_starttls_auto: true
}

Mail.defaults { delivery_method :smtp, smtp }
