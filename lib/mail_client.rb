# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'rest-client'
require_relative 'constants.rb'

# mail client class
class MailClient
  HOST = (ENV.key?('MAIL_HOST') ? ENV['MAIL_HOST'] : MAIL_HOST)
  PORT = (ENV.key?('MAIL_PORT') ? ENV['MAIL_PORT'] : MAIL_PORT).to_i
  def initialize(host = HOST, port = PORT)
    @host = host
    @port = port
  end

  def send_mail(mail_json)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/send_mail_yaml")
    resource.post(mail_json)
  end
end
