#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'sinatra'

require_relative './views/get_job_yaml'
require_relative './views/get_job_content'
require_relative './views/check_job_credible'
require_relative './views/get_compare_result'
require_relative './views/get_error_messages'

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

post '/check_job_credible' do
  begin
    data = JSON.parse(Base64.decode64(request.body.read))
    result = check_job_credible(data['pre_job_id'], data['cur_job_id'], data['error_id'])
  rescue StandardError => e
    return [400, e.backtrace.inspect]
  end

  return [200, {'credible' => result}.to_json]
end

get '/get_job_content/:job_id' do
  begin
    result = get_job_content(params[:job_id])
  rescue StandardError => e
    return [400, e.backtrace.inspect]
  end

  return [200, result.to_json]
end

get '/get_compare_errors/*,*' do |pre_id, cur_id|
  begin
    result = get_compare_errors(pre_id, cur_id)
  rescue StandardError => e
    return [400, e.backtrace.inspect]
  end

  return [200, result.to_json]
end

post '/get_error_messages' do
  begin
    data = JSON.parse(Base64.decode64(request.body.read))
    result = get_error_messages(data['job_id'], data['error_id'])
  rescue StandardError => e
    return [400, e.backtrace.inspect]
  end

  return [200, result.to_json]
end
