#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'sinatra'
require 'open3'
require 'json'
require 'yaml'
require_relative 'get_account_info'

set :bind, '0.0.0.0'
set :port, 10000

post '/assign_account' do
  begin
    data = JSON.parse request.body.read
  rescue StandardError => e
    puts e.message
    puts e.backtrace
  end

  assign_jumper_account(data)
end

def assign_jumper_account(data)
  lacked_info = %w[my_email my_name my_token] - data.keys
  error_message = "lack of my infos: #{lacked_info.join(', ')}."
  raise error_message unless lacked_info.empty?

  ref_account_info = AccountStorage.new(data)
  account_info = ref_account_info.setup_jumper_account_info

  return account_info.to_json
end
