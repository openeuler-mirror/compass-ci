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

def store_email(mail)
  time_now = Time.new.strftime('%Y%m%d%H%M%S')
  file_name = [mail.to[0], time_now].join('_')
  file_full_name = File.join(ENV['SENT_MAILDIR'], 'new', file_name)
  File.open(file_full_name, 'w') do |f|
    f.puts mail
  end
  FileUtils.chown_R(1144, 1110, file_full_name)
end
