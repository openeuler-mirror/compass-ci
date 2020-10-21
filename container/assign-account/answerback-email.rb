#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

# xx --email xxx --login --ssh-pubkey xxx --raw-email email-file
# samba mount
# ssh logshn (huawei, ) (install pubkey / send password)

require 'json'
require 'mail'
require 'set'
require 'optparse'
require_relative '../defconfig'

names = Set.new %w[
  JUMPER_HOST
  JUMPER_PORT
  SEND_MAIL_HOST_INTERNET
  SEND_MAIL_PORT_INTERNET
]

defaults = relevant_defaults(names)

JUMPER_HOST = defaults['JUMPER_HOST'] || 'api.compass-ci.openeuler.org'
JUMPER_PORT = defaults['JUMPER_PORT'] || 29999
SEND_MAIL_HOST = defaults['SEND_MAIL_HOST_INTERNET'] || 'localhost'
SEND_MAIL_PORT = defaults['SEND_MAIL_PORT_INTERNET'] || 11312

$apply_info = {
  'my_email' => nil,
  'my_ssh_pubkey' => nil
}

def init_info(email_file)
  mail_content = Mail.read(email_file)

  $apply_info['my_email'] = mail_content.from[0]
  $apply_info['my_ssh_pubkey'] = if mail_content.part[1].filename == 'id_rsa.pub'
                                   mail_content.part[1].body.decoded.gsub(/\r|\n/, '')
                                 end

  $apply_info
end

options = OptionParser.new do |opts|
  opts.banner = "Usage: answerback-mail.rb [--email email] [--ssh-pubkey pub_key_file] [--raw-email email_file]\n"
  opts.banner += "       -e or -f is required\n"
  opts.banner += '       -s is optional when use -e'

  opts.separator ''
  opts.separator 'options:'

  opts.on('-e|--email email_address', 'appoint email address') do |email_address|
    $apply_info['my_email'] = email_address
  end

  opts.on('-s|--ssh-pubkey pub_key_file', 'ssh pub_key file, enable password-less login') do |pub_key_file|
    $apply_info['my_ssh_pubkey'] = File.read(pub_key_file)
  end

  opts.on('-f|--raw-email email_file', 'email file') do |email_file|
    init_info(email_file)
  end

  opts.on_tail('-h|--help', 'show this message') do
    puts opts
    exit
  end
end

options.parse!(ARGV)

def build_message(email, acct_infos)
  message = <<~EMAIL_MESSAGE
    To: #{email}
    Subject: jumper account is ready

    Dear user:

      Thank you for joining us.
      You can use the following command to login the jumper server:

      login command:
        ssh -p #{acct_infos['jumper_port']} #{acct_infos['account']}@#{acct_infos['jumper_ip']}

      account password:
        #{acct_infos['passwd']}

    regards
    compass-ci
  EMAIL_MESSAGE

  return message
end

def account_info(pub_key)
  account_info_str = if pub_key.nil?
                       %x(curl -XGET '#{JUMPER_HOST}:#{JUMPER_PORT}/assign_account')
                     else
                       %x(curl -XGET '#{JUMPER_HOST}:#{JUMPER_PORT}/assign_account' -d "pub_key: #{pub_key}")
                     end
  JSON.parse account_info_str
end

def send_account
  message = "No email address specified\n"
  message += "use -e email_address add a email address\n"
  message += 'or use -f to add a email file'
  raise message if $apply_info['my_email'].nil?

  acct_info = account_info($apply_info['my_ssh_pubkey'])

  message = build_message($apply_info['my_email'], acct_info)

  %x(curl -XPOST '#{SEND_MAIL_HOST}:#{SEND_MAIL_PORT}/send_mail_text' -d "#{message}")
end

send_account
