#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'sinatra'
require 'open3'
require 'json'
require 'yaml'
require_relative 'get_account_info.rb'

set :bind, '0.0.0.0'
set :port, 29999

get '/assign_account' do
  begin
    data = YAML.safe_load request.body.read
  rescue StandardError => e
    puts e.message
  end

  ref_account_info = AccountStorage.new(data)
  account_info = ref_account_info.setup_jumper_account_info

  return account_info.to_json
end
