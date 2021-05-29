# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require "./lib/create_secrets_yaml"
require "./delimiter/delimiter"

begin
  config_secrets_yaml("delimiter")
  delimiter = Delimiter.new
  delimiter.consume_delimiter("delimiter")
rescue ex
  puts ex
end
