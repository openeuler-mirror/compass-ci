# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

PERFORMANCE_RESULT_INPUT_KEYS = Set.new(['metrics', 'filter', 'series', 'x_params'])
PERFORMANCE_RESULT_IGNORE_KEYS = Set.new(['max_series_num'])

# --------------------------------------------------------------------------------------------
# check the input params for API: web-backend/performance_result
# the correct input should like:
#     {
#       "metrics": ["fio.write_iops", "fio.read_iops"],
#       "filter":{"suite": ["fio-basic"],"os_arch": ["aarch64", "x86"]},
#       "series": [{"os": "debian"},{"os": "openeuler"},
#       "x_params": ["bs", "test_size"]
#     }
# --------------------------------------------------------------------------------------------
def check_performance_result(request_body)
  lack_param = lack_params?(PERFORMANCE_RESULT_INPUT_KEYS, Set.new(request_body.keys))
  return lack_param if lack_param

  request_body.each do |key, value|
    next if (PERFORMANCE_RESULT_INPUT_KEYS | PERFORMANCE_RESULT_IGNORE_KEYS).include?(key)

    return "incorrerct input \"#{key}\""
  end

  return nil
end

# @request_keys: Set
# @expect_keys: Set
#   eg: #<Set: {"metrics", "filter", "series", "x_params"}>
def lack_params?(expect_keys, request_keys)
  subtraction = expect_keys ^ request_keys
  return false if subtraction.empty? || subtraction == PERFORMANCE_RESULT_IGNORE_KEYS

  lack_params = subtraction & expect_keys
  return false if lack_params.empty? || lack_params == PERFORMANCE_RESULT_IGNORE_KEYS

  msg = 'lack params: '
  lack_params.each do |param|
    msg += "\"#{param}\", "
  end

  msg + 'please check you request'
end
