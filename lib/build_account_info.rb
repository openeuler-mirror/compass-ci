#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './es_client'
require_relative './build_my_info_client'

def search_account_info(build_my_info)
  info_es = build_my_info.search_my_info

  [info_es, build_my_info]
end

def build_account_info(option)
  build_my_info = BuildMyInfo.new(option['my_email'])

  info_es, build_my_info = search_account_info(build_my_info)

  my_ssh_pubkey = option.delete('my_ssh_pubkey') unless option['my_ssh_pubkey'].nil?

  info_es.update option

  info_es['my_token'] = %x(uuidgen).chomp if info_es['my_token'].nil?
  info_es['my_ssh_pubkey'] = [] if info_es['my_ssh_pubkey'].nil?
  unless my_ssh_pubkey.nil? || my_ssh_pubkey.empty?
    info_es['my_ssh_pubkey'] = info_es['my_ssh_pubkey'] + my_ssh_pubkey
    info_es['my_ssh_pubkey'].uniq!
  end

  check_required_keys(info_es)

  unless check_account_unique(info_es, build_my_info)
    error_msg = "Offered my_account: #{info_es['my_account']} is already used!\n"
    error_msg += "Please use a new one and try again."

    raise error_msg
  end

  build_my_info.config_my_info(info_es)
end

# the my_account has a attribute of unique.
# when we add/update the my_account,
# we should firstly check the value of my_account already exists,
def check_account_unique(info_es, build_my_info)
  email = info_es['my_email']
  key = 'my_account'
  value = info_es[key]

  return true if build_my_info.check_item_unique(email, key, value)

  return false
end

def check_required_keys(info_es)
  required_keys = %w[my_email my_name my_account lab my_ssh_pubkey]
  lacked_keys = required_keys - info_es.keys

  raise "Lack of required keys: #{lacked_keys.join(", ")}" unless lacked_keys.empty?
end
