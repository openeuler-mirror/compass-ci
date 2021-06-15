#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './es_client'
require_relative './build_my_info_client'

def build_account_info(option)
  build_my_info = BuildMyInfo.new(option['my_email'])
  info_es = build_my_info.search_my_info
  info_es.update option
  info_es['my_token'] = %x(uuidgen).chomp if info_es['my_token'].nil?
  info_es['my_ssh_pubkey'] = []

  build_my_info.config_my_info(info_es)
end
