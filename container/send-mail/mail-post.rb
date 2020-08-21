#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'open3'
require_relative 'send-mail.rb'

set :bind, '0.0.0.0'
set :port, 8101

post '/send_mail' do
  request.body.rewind
  begin
    puts 'hh'
    data = JSON.parse request.body.read
  rescue JSON::ParserError
    return [400, headers.update({ 'errcode' => '100', 'errmsg' => 'parse json error' }), '']
  end
  puts '-' * 50
  puts 'post body:', data

  to = data['to']
  body = data['body']
  subject = data['subject']
  begin
    send_mail(subject, to, body)
  rescue StandardError => e
    puts 'error message: ', e.message
    return [400, headers.update(JSON.parse(e.message)), '']
  end
  [200, headers.update({ 'errcode' => '0' })]
end
