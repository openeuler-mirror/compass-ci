# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative "#{ENV['CCI_SRC']}/lib/compare_error_messages"

def get_error_messages(job_id, error_id)
  return  CEM.get_error_messages(job_id, error_id)
end
