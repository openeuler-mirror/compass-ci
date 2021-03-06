# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./sched"
require "./lifecycle"
require "./json_logger"
require "./updaterepo"

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

    def lifecycle
      @lifecycle ||= create_lifecycle
    end

    def create_lifecycle
      @lifecycle = Lifecycle.new(self)
    end

    def repo
      @repo ||= create_repo
    end

    def create_repo
      @repo = Repo.new(self)
    end
  end
end
