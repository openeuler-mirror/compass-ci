# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"

require "../lib/web_env"
require "../lib/updaterepo"
require "../lib/json_logger"

module Updaterepo
  VERSION = "0.1.0"
  post "/upload" do |env|
    env.repo.upload_repo
    "done"
  end
end
