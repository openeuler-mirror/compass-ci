#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

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
end
