# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"

require "../lib/web_env"
require "../lib/lifecycle"
require "../lib/json_logger"

module Cycle
  VERSION = "0.1.0"

  add_context_storage_type(Time::Span)

  before_all do |env|
    env.set "start_time", Time.monotonic
    env.response.headers["Connection"] = "close"
    env.create_log
    env.create_lifecycle
  end

  # echo alive
  get "/" do |env|
    env.lifecycle.alive(VERSION)
  end

  # find the testbox that are performing jobs
  # curl http://localhost:11311/get_running_testbox?size=10&from=0
  get "/get_running_testbox" do |env|
    env.lifecycle.get_running_testbox.to_json
  end
end
