# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"

require "../lib/web_env"
require "../lib/lifecycle"
require "../lib/json_logger"

module Cycle
  VERSION = "0.1.0"
  get "/" do |_env|
    "done"
  end
end
