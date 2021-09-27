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

    def channel
      @channel ||= create_channel
    end

    def create_channel
      @channel = Channel(Hash(String, JSON::Any) | Hash(String, String)).new
    end

    def watch_channel
      @watch_channel ||= create_watch_channel
    end

    def create_watch_channel
      @watch_channel = Channel(Array(Etcd::Model::WatchEvent) | String).new
    end

    def socket
      @socket.as(HTTP::WebSocket)
    end

    def create_socket(socket : HTTP::WebSocket)
      @socket = socket
    end

    def cluster
      @cluster ||= create_cluster
    end

    def create_cluster
      @cluster = Cluster.new
    end

    def pkgbuild
      @pkgbuild ||= create_pkgbuild
    end

    def create_pkgbuild
      @pkgbuild = PkgBuild.new
    end

    def finally
      @finally ||= create_finally
    end

    def create_finally
      @finally = Finally.new
    end
  end
end
