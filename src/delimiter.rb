# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './delimiter/delimiter'

begin
  delimiter = Delimiter.new
  delimiter.start_delimit
rescue StandardError => e
  puts e
end
