#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'mail'
require 'rest-client'
require_relative '../../../lib/es_client'
require_relative 'assign-account-email'
require_relative 'assign-account-fail-email'
require_relative 'apply-jumper-account'
require_relative 'parse-apply-account-email'

SEND_MAIL_PORT = ENV['SEND_MAIL_PORT'] || 10001

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
#         - my_token
#       my_ssh_pubkey
#   store_account_info
#     call ESClient to store my_info
#       my_info:
#         - my_email
#         - my_name
#         - my_token
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
    @es_host = @send_mail_host
    @es_port = ES_PORT

    # email info file for account issuers.
    @account_issuer = File.exist?(ENV['ACCOUNT_ISSUER']) ? YAML.load_file(ENV['ACCOUNT_ISSUER']) : {}

    @my_info = {
      'account_vm' => false,
      'enable_login' => true
    }
  end

  def check_to_send_account
    # in case of failed parsing, parse_mail_content will return none info
    # in order to successfully send email for failed parsing
    # firstly get my_email before execute parse_mail_content is needed
    @my_info['my_email'] = @mail_content.from[0]

    # for the forwarded email, it contains my_email/my_name .etc.
    # all emails from account issuer  will be treated as forwarded emails.
    # the mail_content may like:
    # ---
    # my_name: name_1
    # my_name: email_1
    # account_vm: true/false/yes/no
    # ---
    # my_name: name_2
    # my_email: email_2
    # ---
    # the forwarded email allowed to contain multi my_email/my_name(s)
    # in this case, we will loop them
    if @account_issuer.include? @my_info['my_email']
      users_info = forward_users
      users_info.each do |user_info|
        # for forwarded email for multi users, avoid rezidual information from the last,
        # need to clear the old data for my_info.
        @my_info.clear
        assign_account_vm = user_info['account_vm']
        @my_info.update user_info

        applying_account(assign_account_vm)
        sleep 5
      end
    else
      parse_mail_content
      applying_account(false)
    end
  rescue StandardError => e
    puts e.message
    puts e.backtrace

    send_mail(e.message, '', '')
  end

  def forward_users
    forward_email_content = ParseApplyAccountEmail.new(@mail_content)
    users_info = forward_email_content.extract_users

    users_info.clone.each_index do |i|
      users_info[i]['my_ssh_pubkey'] = []
      users_info[i]['lab'] = ENV['lab']
    end

    users_info
  end

  def applying_account(assign_account_vm)
    account_info = apply_my_account
    store_account_info
    send_mail('', account_info, assign_account_vm)
  end

  def parse_mail_content
    parse_apply_account_email = ParseApplyAccountEmail.new(@mail_content)

    parsed_email_info = parse_apply_account_email.build_my_info

    @my_info.update parsed_email_info
  end

  def read_my_account_es
    account_es = ESQuery.new(index: 'accounts')
    account_es.query_by_id(@my_info['my_email'])
  end

  def build_apply_info(apply_info, my_account_es)
    my_ssh_pubkey_new = @my_info.delete('my_ssh_pubkey')
    apply_info['my_token'] = my_account_es['my_uuid'] if my_account_es['my_token'].nil?
    apply_info.update my_account_es
    apply_info.update @my_info
    if my_ssh_pubkey_new
      apply_info['my_ssh_pubkey'] = (apply_info['my_ssh_pubkey'] + my_ssh_pubkey_new).uniq
    end
    @my_info.update apply_info
    apply_info['is_update_account'] = true
    apply_info
  end

  def apply_my_account
    my_account_es = read_my_account_es
    apply_info = {}

    if my_account_es
      build_apply_info(apply_info, my_account_es)
    else
      my_token = %x(uuidgen).chomp
      @my_info['my_token'] = my_token
      apply_info.update @my_info
    end
    apply_new_account(apply_info, my_account_es)
  end

  def apply_new_account(apply_info, my_account_es)
    apply_account = ApplyJumperAccount.new(apply_info)
    acct_info = apply_account.apply_jumper_account

    @my_info['my_login_name'] = acct_info['my_login_name'] unless my_account_es
    acct_info
  end

  def store_account_info
    es = ESClient.new(index: 'accounts')
    es.put_source_by_id(@my_info['my_email'], @my_info)
  end

  def send_mail(error_message, account_info, assign_account_vm)
    email_message = if error_message.empty?
                      build_apply_account_email(@my_info, account_info, assign_account_vm)
                    else
                      build_apply_account_fail_email(@my_info, error_message)
                    end

    send_mail_url = "#{@send_mail_host}:#{@send_mail_port}/send_mail_text"
    RestClient.post send_mail_url, email_message
  end
end
