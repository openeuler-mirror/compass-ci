#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './es_client'
require_relative './build_my_info_client'

def search_account_info(option)
  build_my_info = BuildMyInfo.new(option['my_email'])
  info_es = build_my_info.search_my_info

  [info_es, build_my_info]
end

def build_account_info(option)
  info_es, build_my_info = search_account_info(option)

  my_ssh_pubkey = option.delete('my_ssh_pubkey') unless option['my_ssh_pubkey'].nil?

  info_es.update option

  info_es['my_token'] = %x(uuidgen).chomp if info_es['my_token'].nil?
  info_es['my_ssh_pubkey'] = [] if info_es['my_ssh_pubkey'].nil?
  unless my_ssh_pubkey.empty?
    info_es['my_ssh_pubkey'] = info_es['my_ssh_pubkey'] + my_ssh_pubkey
    info_es['my_ssh_pubkey'].uniq!
  end

  build_my_info.config_my_info(info_es)
end
