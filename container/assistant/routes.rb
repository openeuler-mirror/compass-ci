#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'open3'

require_relative './views/locate_files'

set :bind, '0.0.0.0'
set :port, 8101

post '/locate_files' do
  request.body.rewind

  begin
    data = JSON.parse request.body.read
  rescue JSON::ParserError
    return [400, 'parse json params error']
  end

  begin
    result = locate_files(data)
  rescue StandardError => e
    return [400, e.backtrace.inspect]
  end

  [200, result.to_json]
end
