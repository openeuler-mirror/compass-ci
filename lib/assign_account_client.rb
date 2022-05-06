#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'set'
require 'optparse'
require 'rest-client'
require_relative '../container/defconfig'
require_relative 'es_client'
require_relative '../container/mail-robot/lib/assign-account-email'
require_relative "#{ENV['CCI_SRC']}/lib/parse_mail_list"

names = Set.new %w[
  JUMPER_HOST
  JUMPER_PORT
  SEND_MAIL_HOST
  SEND_MAIL_PORT
]

defaults = relevant_defaults(names)
JUMPER_HOST = defaults['JUMPER_HOST']
JUMPER_PORT = defaults['JUMPER_PORT'] || 10000
SEND_MAIL_HOST = defaults['SEND_MAIL_HOST'] || 'localhost'
SEND_MAIL_PORT = defaults['SEND_MAIL_PORT'] || 10001
LAB = ENV['lab']

# used for other codes calling to assign account for user
class AutoAssignAccount
  def initialize(user_info)
    @my_info = user_info

    @my_info_es = {}
    @account_info = {}
  end

  def update_from_es
    account_infos = ESQuery.new(index: 'accounts')
    my_account_info = account_infos.query_by_id(@my_info['my_email']) || {}

    my_account_info.update @my_info
    @my_info.update my_account_info
    @my_info['my_ssh_pubkey'] = [] unless my_account_info['my_ssh_pubkey']

    @my_info['my_token'] = %x(uuidgen).chomp if @my_info['my_login_name'].nil?
  end

  def apply_account
    apply_info = {}

    apply_info.update @my_info
    apply_info['enable_login'] = true
    apply_info['is_update_account'] = true unless apply_info['my_login_name'].nil?
    apply_info['lab'] = LAB

    assign_account_url = "#{JUMPER_HOST}:#{JUMPER_PORT}/assign_account"
    account_info_str = RestClient.post assign_account_url, apply_info.to_json
    JSON.parse account_info_str
  end

  def update_my_info_from_account_info
    @account_info = apply_account

    @my_info['my_login_name'] = @account_info['my_login_name']
    @my_info['my_ssh_pubkey'] << @account_info['my_jumper_pubkey'] unless @account_info['my_jumper_pubkey'].nil?
  end

  def store_account_info
    es = ESClient.new(index: 'accounts')
    es.put_source_by_id(@my_info['my_email'], @my_info)
  end

  def send_mail
    @my_info['bisect'] = true
    default_email = parse_mail_list('delimiter')
    @my_info['my_email'] = default_email['to'] unless default_email.empty?
    message = build_apply_account_email(@my_info, @account_info, false)
    %x(curl -XPOST "#{SEND_MAIL_HOST}:#{SEND_MAIL_PORT}/send_mail_text" -d "#{message}")
  end

  def send_account
    update_from_es
    update_my_info_from_account_info

    store_account_info
    send_mail
  end
end
