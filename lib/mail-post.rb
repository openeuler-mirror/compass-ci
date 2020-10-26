#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'yaml'
require 'open3'
require 'mail'

set :bind, '0.0.0.0'
set :port, ENV['SEND_MAIL_PORT']

post '/send_mail_yaml' do
  data = YAML.safe_load request.body.read
  raise TypeError, data, 'request data type error' unless data.is_a? Hash

  mail_info = {
    'subject' => data['subject'],
    'to' => data['to'],
    'body' => data['body']
  }

  check_send_mail(mail_info)
end

post '/send_mail_text' do
  data = Mail.read_from_string(request.body.read)

  mail_info = {
    'subject' => data.subject,
    'to' => data.to,
    'body' => data.body.decoded
  }

  send_mail(mail_info)
end

def check_send_mail(mail_info)
  raise 'no/empty subject.' if mail_info['subject'].nil? || mail_info['subject'].empty?
  raise 'no/empty email_to address.' if mail_info['to'].nil? || mail_info['to'].empty?
  raise 'no/empty email content.' if mail_info['body'].nil? || mail_info['body'].empty?
end

def send_mail(mail_info)
  check_send_mail(mail_info)
  mail = Mail.new do
    from ENV['ROBOT_EMAIL_ADDRESS']
    subject mail_info['subject']
    to mail_info['to']
    body mail_info['body']
  end
  mail.deliver!
end
