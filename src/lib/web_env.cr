# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./sched"
require "./json_logger"

class HTTP::Server
  # Instances of this class are passed to an `HTTP::Server` handler.
  class Context
    def create_log
      @log = JSONLogger.new(env: self)
    end

    def log
      @log ||= create_log
    end

    def channel
      @channel ||= create_channel
    end

    def create_channel
      @channel = Channel(Hash(String, JSON::Any) | Hash(String, String)).new
    end

  end
end
