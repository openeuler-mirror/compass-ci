# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'rest-client'
require_relative 'constants'

# sched client class
class SchedClient
  def initialize(host = SCHED_HOST, port = SCHED_PORT)
    @host = host
    @port = port
  end

  def submit_job(job_json)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/submit_job")
    resource.post(job_json)
  end
end
