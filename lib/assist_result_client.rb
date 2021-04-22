#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'base64'
require 'rest-client'
require_relative 'constants'

class AssistResult
  def initialize(host = ASSIST_RESULT_HOST, port = ASSIST_RESULT_PORT)
    @host = host
    @port = port
  end

  def get_job_yaml(job_id)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/get_job_yaml/#{job_id}")
    response = resource.get()
    return nil unless response.code == 200

    return response.body
  end

  def check_job_credible(pre_job_id, cur_job_id, error_id)
    data = {
      'pre_job_id' => pre_job_id,
      'cur_job_id' => cur_job_id,
      'error_id' => error_id
    }
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/check_job_credible")
    response = resource.post(Base64.encode64(data.to_json))
    return nil unless response.code == 200

    return JSON.parse(response.body)
  end

  def get_job_content(job_id)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/get_job_content/#{job_id}")
    response = resource.get()
    return nil unless response.code == 200

    return response.body
  end

  def get_compare_errors(pre_id, cur_id)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/get_compare_errors/#{pre_id},#{cur_id}")
    response = resource.get()
    return nil unless response.code == 200

    return JSON.parse(response.body)
  end

  def get_error_messages(job_id, error_id)
    data = {
      'job_id' => job_id,
      'error_id' => error_id
    }
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/get_error_messages")
    response = resource.post(Base64.encode64(data.to_json))
    return nil unless response.code == 200

    return JSON.parse(response.body)
  end
end
