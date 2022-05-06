#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'yaml'
require 'open3'
require 'mail'
require 'base64'

require_relative 'mail-post/email_init'
require_relative 'mail-post/email_limit_queue'
require_relative 'mail-post/email_mapping'

set :bind, '0.0.0.0'
set :port, ENV['SEND_MAIL_PORT']

post '/send_mail_yaml' do
  data = YAML.safe_load request.body.read
  raise TypeError, data, 'request data type error' unless data.is_a? Hash

  mail_info = {
    'subject' => data['subject'],
    'to' => data['to'],
    'cc' => data['cc'],
    'bcc' => data['bcc'],
    'body' => data['body'],
    'attach_name' => data['attach_name'],
    'attach_content' => data['attach_content']
  }

  send_mail(mail_info)
end

post '/send_mail_text' do
  data = Mail.read_from_string(request.body.read)

  mail_info = {
    'subject' => data.subject,
    'to' => data.to,
    'cc' => data.cc,
    'bcc' => data.bcc,
    'body' => data.body.decoded
  }

  send_mail(mail_info)
end

post '/send_mail_encode' do
  data_decode = Base64.decode64(request.body.read)
  data = Mail.read_from_string(data_decode)

  mail_info = {
    'subject' => data.subject,
    'to' => data.to,
    'cc' => data.cc,
    'bcc' => data.bcc,
    'body' => data.body.decoded
  }

  send_mail(mail_info)
end

def check_email_limit(mail_info)
  email_limit = EmailRateLimit.new(mail_info)
  email_limit.check_email_counts
end

def check_email_mapping(mail_info)
  email_mapping = EmailAddrMapping.new(mail_info)
  email_mapping.check_email_mapping
end

def check_send_mail(mail_info)
  raise 'no/empty subject.' if mail_info['subject'].nil? || mail_info['subject'].empty?
  raise 'no/empty email_to address.' if mail_info['to'].nil? || mail_info['to'].empty?
  raise 'no/empty email content.' if mail_info['body'].nil? || mail_info['body'].empty?

  return mail_info unless ENV['SEND_MAIL_PORT'].to_s == '10001'

  mail_info = check_email_mapping(mail_info.clone)
  mail_info = check_email_limit(mail_info.clone)
  return mail_info
end

def send_mail(mail_info)
  mail_info = check_send_mail(mail_info)
  return if mail_info['to'].empty?

  mail = Mail.new do
    from ENV['ROBOT_EMAIL_ADDRESS']
    subject mail_info['subject']
    to mail_info['to']
    cc mail_info['cc']
    bcc mail_info['bcc']
    body mail_info['body']

    if mail_info.key?('attach_name') && mail_info['attach_name']
      add_file filename: mail_info['attach_name'], content: mail_info['attach_content']
    end
  end

  mail.deliver!
  check_to_store_email(mail)
end

def check_to_store_email(mail)
  return if ENV['SEND_MAIL_PORT'].to_s != '10001'
  return if ENV['HOST_SERVER'] != 'z9'

  store_email(mail)
end
