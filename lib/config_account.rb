#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative "./build_my_info_client"
require_relative "../container/defconfig"

def my_email(account)
  names = %W(#{account})

  defaults = relevant_defaults(names)
  defaults[account]['my_email']
end

def config_yaml(account)
  build_my_info = BuildMyInfo.new(my_email(account))

  my_info = build_my_info.search_my_info

  for i in 1..20
    break if my_info['my_email']
    sleep(6)
    my_info = build_my_info.search_my_info
  end

  build_my_info.config_default_yaml(my_info)
  build_my_info.config_lab_yaml(my_info)
end
