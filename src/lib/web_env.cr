# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./sched"
require "./json_logger"

class HTTP::Server
  # Instances of this class are passed to an `HTTP::Server` handler.
  class Context
    def create_sched
      @sched = Sched.new(self)
    end

    def sched
      @sched ||= create_sched
    end

    def create_log
      @log = JSONLogger.new(env: self)
    end

    def log
      @log ||= create_log
    end
  end
end
