# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative "#{ENV['CCI_SRC']}/lib/parse_mail_list"

def get_mail_list(type)
  return parse_mail_list(type)
end
