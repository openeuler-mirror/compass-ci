# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./updaterepo/updaterepo"
require "./updaterepo/constants"
require "./lib/json_logger"


module Updaterepo
  log = JSONLogger.new

  begin
    Kemal.run(REPO_PORT)
  rescue e
    log.error(e)
  end
end
