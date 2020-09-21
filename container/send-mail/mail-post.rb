#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'yaml'
require 'open3'
require_relative 'send-mail.rb'

set :bind, '0.0.0.0'
set :port, 11311

post '/send_mail_yaml' do
  data = YAML.safe_load request.body.read
  raise TypeError, data, 'request data type error' unless data.class.eql? Hash

  mail_info = {
    'references' => data['references'] || '',
    'from' => data['from'] || 'team@crystal.ci',
    'subject' => data['subject'],
    'to' => data['to'],
    'body' => data['body']
  }
  check_send_mail(mail_info)
end

post '/send_mail_text' do
  data = Mail.read_from_string(request.body.read)

  mail_info = {
    'references' => data.references || '',
    'from' => data.from || 'team@crystal.ci',
    'subject' => data.subject,
    'to' => data.to,
    'body' => data.body.decoded
  }
  check_send_mail(mail_info)
end

def check_send_mail(mail_info)
  raise TypeError, data, 'empty subject.' if mail_info['subject'].empty?
  raise TypeError, data, 'empty email address.' if mail_info['to'].empty?
  raise TypeError, data, 'empty email content.' if mail_info['body'].empty?

  send_mail(mail_info)
end
