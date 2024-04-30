# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "uri"
require "yaml"
require "json"
require "any_merge"
require "elasticsearch-crystal/elasticsearch/api"
require "elasticsearch-crystal/elasticsearch/api/utils"
require "./constants"

class ES::Client
  class_property :client
  HOST = (ENV.has_key?("ES_HOST") ? ENV["ES_HOST"] : JOB_ES_HOST)
  PORT = (ENV.has_key?("ES_PORT") ? ENV["ES_PORT"] : JOB_ES_PORT).to_i32

  def initialize(host = HOST, port = PORT, auth = true)
    if auth
      user = ENV["ES_USER"]?
      password = ENV["ES_PASSWORD"]?
      host = "#{user}:#{URI.encode_www_form(password)}@#{host}" if user && password
    end
    @host = host.as(String)
    @port = port.to_s.as(String)
    @client = Elasticsearch::API::Client.new({:host => host, :port => port})
  end

  def search(index, query)
    results = @client.search({:index => index, :body => query})

    return results
  end
end
