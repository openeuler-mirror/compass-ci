#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'sinatra'

require_relative './views/get_job_yaml'

configure do
  set :bind, '0.0.0.0'
  set :port, ENV['ASSIST_RESULT_PORT']
end

get '/get_job_yaml/:job_id' do
  begin
    result = get_job_yaml(params[:job_id])
  rescue StandardError => e
    return [400, e.backtrace.inspect]
  end

  return [200, result.to_json]
end
