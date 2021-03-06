# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'net/http'
#:nodoc:
class LkpServerInfo
  attr_accessor :host, :port

  def initialize(host = '127.0.0.1', port = '3000')
    @host = host
    @port = port
  end

  def connect_able
    url = URI("http://#{@host}:#{@port}")
    http = Net::HTTP.new(url.host, url.port)

    begin
      response = http.get(url)
      case response.code
      when '200', '401'
        true
      else
        false
      end
    rescue exception
      false
    end
  end
end
