#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'open3'

require_relative './views/locate_files'
require_relative './views/get_mail_list'

configure do
  set :bind, '0.0.0.0'
  set :port, ENV['ASSISTANT_PORT']
end

post '/locate_files' do
  request.body.rewind

  begin
    data = JSON.parse request.body.read
    result = locate_files(data)
  rescue StandardError => e
    return [400, e.backtrace.inspect]
  end

  [200, result.to_json]
end

get '/get_mail_list/:type' do
  begin
    result = get_mail_list(params[:type])
  rescue StandardError => e
    return [400, e.backtrace.inspect]
  end

  return [200, result.to_json]
end
