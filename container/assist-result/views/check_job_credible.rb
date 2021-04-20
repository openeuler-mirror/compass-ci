# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative "#{ENV['CCI_SRC']}/lib/compare_error_messages"

def check_job_credible(pre_job_id, cur_job_id, error_id)
  return CEM.credible?(pre_job_id, cur_job_id, error_id)
end
