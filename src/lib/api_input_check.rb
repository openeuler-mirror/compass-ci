# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

PERFORMANCE_RESULT_INPUT_KEYS = ['metrics', 'filter', 'series', 'x_params']

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
  request_body.each do |key, value|
    next if PERFORMANCE_RESULT_INPUT_KEYS.include?(key)

    return "incorrerct input \"#{key}\""
  end

  return nil
end
