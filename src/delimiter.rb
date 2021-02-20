# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './delimiter/delimiter'
require_relative '../lib/config_account'

begin
  config_yaml('delimiter')
  delimiter = Delimiter.new
  delimiter.start_delimit
rescue StandardError => e
  puts e
end
