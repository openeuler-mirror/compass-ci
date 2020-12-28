#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'

JUMPER_HOST = ENV['JUMPER_HOST'] || 'api.compass-ci.openeuler.org'
JUMPER_PORT = ENV['JUMPER_PORT'] || 29999

# used to apply account
# be called after AssignAccount successfully parsed my_commit_url and my_ssh_pubkey
# apply_jumper_account
#   apply jumper account with my_info and my_ssh_pubkey
# account_info_exist
#   check account exists
class ApplyJumperAccount
  def initialize(my_info)
    @jumper_host = JUMPER_HOST
    @jumper_port = JUMPER_PORT
    @my_info = my_info.clone
  end

  def apply_jumper_account
    assign_account_url = "#{JUMPER_HOST}:#{JUMPER_PORT}/assign_account"
    account_info_str = RestClient.post assign_account_url, @my_info.to_json
    account_info = JSON.parse account_info_str

    account_info_exist(account_info)

    return account_info
  end

  def account_info_exist(account_info)
    return unless account_info['my_login_name'].nil?

    error_message = 'No more available jumper account.'
    error_message += 'You may try again later or consulting the manager for a solution.'

    raise error_message
  end
end
