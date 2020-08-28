#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'yaml'
require 'open3'
require_relative 'send-mail.rb'

set :bind, '0.0.0.0'
set :port, 8101

post '/send_mail_yaml' do
  data = YAML.safe_load request.body.read
  raise TypeError, data, 'request data type error' unless data.class.eql? Hash

  subject = data['subject']
  to = data['to']
  body = data['body']
  to_send_mail(subject, to, body)
end

post '/send_mail_text' do
  data = Mail.read_from_string(request.body.read)
  subject = data.subject
  to = data.to
  body = data.body.decoded
  to_send_mail(subject, to, body)
end

def to_send_mail(subject, to, body)
  raise TypeError, data, 'empty subject.' if subject.empty?
  raise TypeError, data, 'empty email address.' if to.empty?
  raise TypeError, data, 'empty email content.' if body.empty?

  send_mail(subject, to, body)
end
