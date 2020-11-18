#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'mail'
require_relative '../../../lib/es_client'
require_relative 'assign-account-email'
require_relative 'assign-account-fail-eamil'
require_relative 'apply-jumper-account'
require_relative 'parse-apply-account-email'

SEND_MAIL_PORT = ENV['SEND_MAIL_PORT'] || 49000

# assign uuid/account for user
# when mail-robot listened new email, and the email's subject
# exactly equal 'apply account', mail-robot will call this class
# entry point: send_account
# input: email's content
#
# send_account
#   parse_mail_content
#     call ParseApplyAccountEmail to parse:
#       - my_commit_url
#       - my_ssh_pubkey
#   apply_my_account
#     call ApplyJumperAccount to apply new account
#     required data:
#       my_info:
#         - my_email
#         - my_name
#         - my_uuid
#       my_ssh_pubkey
#   store_account_info
#     call ESClient to store my_info
#       my_info:
#         - my_email
#         - my_name
#         - my_uuid
#         - my_commit_url
#         - my_login_name
#         - my_ssh_pubkey
#   send_mail
#     when successfully applied an account
#       call build_apply_account_email to send a successful email
#     when rescued error message
#       call build_apply_account_fail_email to send fail email
class ApplyAccount
  def initialize(mail_content)
    @send_mail_host = %x(/sbin/ip route | awk '/default/ {print $3}').chomp
    @send_mail_port = SEND_MAIL_PORT
    @mail_content = mail_content

    @my_info = {}
  end

  def check_to_send_account
    # in case of failed parsing, parse_mail_content will return none info
    # in order to successfully send email for failed parsing
    # firstly get my_email before execute parse_mail_content is needed
    @my_info['my_email'] = @mail_content.from[0]
    parse_mail_content
    acct_info = apply_my_account

    @my_info['my_login_name'] = acct_info['my_login_name']

    store_account_info
    send_mail('')
  rescue StandardError => e
    puts e.message
    puts e.backtrace

    send_mail(e.message)
  end

  def parse_mail_content
    parse_apply_account_email = ParseApplyAccountEmail.new(@mail_content)

    parsed_email_info = parse_apply_account_email.build_my_info

    @my_info.update parsed_email_info
  end

  def apply_my_account
    my_uuid = %x(uuidgen).chomp

    @my_info['my_uuid'] = my_uuid

    apply_account = ApplyJumperAccount.new(@my_info)
    acct_info = apply_account.apply_jumper_account

    return acct_info
  end

  def store_account_info
    es = ESClient.new(index: 'accounts')
    es.put_source_by_id(@my_info['my_email'], @my_info)
  end

  def send_mail(error_message)
    email_message = if error_message.empty?
                      build_apply_account_email(@my_info)
                    else
                      build_apply_account_fail_email(@my_info, error_message)
                    end

    %x(curl -XPOST "#{@send_mail_host}:#{@send_mail_port}/send_mail_text" -d "#{email_message}")
  end
end
