# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative "#{ENV['CCI_SRC']}/lib/compare_error_messages"

def get_compare_errors(pre_id, cur_id)
  _, errors = CEM.get_compare_result(pre_id, cur_id)
  return errors
end
