# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"
require "yaml"

require "./web_env"
require "../scheduler/elasticsearch_client"

class Lifecycle
  property es

  def initialize(env : HTTP::Server::Context)
    @es = Elasticsearch::Client.new
    @env = env
    @log = env.log.as(JSONLogger)
  end

  def alive(version)
    "Lifecycle Alive! The time is #{Time.local}, version = #{version}"
  rescue e
    @log.warn(e)
  end

  def get_running_testbox
    size = @env.params.query["size"]? || 20
    from = @env.params.query["from"]? || 0
    query = {
      "size" => size,
      "from" => from,
      "query" => {
        "terms" => {
          "state" => ["booting", "running"]
        }
      }
    }
    @es.search("testbox", query)
  end
end
