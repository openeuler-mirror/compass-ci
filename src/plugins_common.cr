# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./lib/json_logger"
require "./lib/remote_git_client"

class PluginsCommon
  def initialize
    @rgc = RemoteGitClient.new
    @log = JSONLogger.new
  end

end
