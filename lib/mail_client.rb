# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'base64'
require 'rest-client'
require_relative 'constants.rb'

# mail client class
class MailClient
  HOST = (ENV.key?('SEND_MAIL_HOST') ? ENV['SEND_MAIL_HOST'] : SEND_MAIL_HOST)
  PORT = (ENV.key?('SEND_MAIL_PORT') ? ENV['SEND_MAIL_PORT'] : SEND_MAIL_PORT).to_i
  def initialize(host: HOST, port: PORT, is_outgoing: true)
    @host = host
    @port = port
    unless is_outgoing
      @host = (ENV.key?('LOCAL_SEND_MAIL_HOST') ? ENV['LOCAL_SEND_MAIL_HOST'] : LOCAL_SEND_MAIL_HOST)
      @port = (ENV.key?('LOCAL_SEND_MAIL_PORT') ? ENV['LOCAL_SEND_MAIL_PORT'] : LOCAL_SEND_MAIL_PORT).to_i
    end
  end

  def send_mail(mail_json)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/send_mail_yaml")
    resource.post(mail_json)
  end

  def send_mail_encode(mail_data)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/send_mail_encode")
    resource.post(Base64.encode64(mail_data))
  end

  def send_mail_text(mail_text)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/send_mail_text")
    resource.post(mail_text)
  end
end
