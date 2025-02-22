# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../redis_client"
require "../elasticsearch_client"
require "../../lib/utils"
require "../../lib/json_logger"
require "../../lib/remote_git_client"
require "../../lib/scheduler_api"

class PluginsCommon
  def initialize
    @rgc = RemoteGitClient.new
    @log = JSONLogger.new
  end

end
