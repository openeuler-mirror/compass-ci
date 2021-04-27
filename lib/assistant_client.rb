#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'base64'
require 'rest-client'
require_relative 'constants'

class AssistantClient
  def initialize(host = ASSISTANT_HOST, port = ASSISTANT_PORT)
    @host = host
    @port = port
  end

  def get_mail_list(type)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/get_mail_list/#{type}")
    response = resource.get()
    return nil unless response.code == 200

    return JSON.parse(response.body)
  end

  def send_account_mail(user_info)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/send_account_mail")
    response = resource.post(user_info.to_json)
    return nil unless response.code == 200

    return JSON.parse(response.body)
  end
end
