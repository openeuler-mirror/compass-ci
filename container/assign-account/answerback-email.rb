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
require_relative '../../lib/es_client'

names = Set.new %w[
  JUMPER_HOST
  JUMPER_PORT
  SEND_MAIL_HOST
  SEND_MAIL_PORT
]

defaults = relevant_defaults(names)

JUMPER_HOST = defaults['JUMPER_HOST'] || 'api.compass-ci.openeuler.org'
JUMPER_PORT = defaults['JUMPER_PORT'] || 29999
SEND_MAIL_HOST = defaults['SEND_MAIL_HOST'] || 'localhost'
SEND_MAIL_PORT = defaults['SEND_MAIL_PORT'] || 49000

my_info = {
  'my_email' => nil,
  'my_name' => nil,
  'my_uuid' => %x(uuidgen).chomp,
  'my_ssh_pubkey' => nil
}

def init_info(email_file, my_info)
  mail_content = Mail.read(email_file)
  my_info['my_email'] = mail_content.from[0]
  my_info['my_name'] = mail_content.From.unparsed_value.gsub(/ <[^<>]*>/, '')
  my_info['my_ssh_pubkey'] = if mail_content.part[1].filename == 'id_rsa.pub'
                               mail_content.part[1].body.decoded
                             end
end

options = OptionParser.new do |opts|
  opts.banner = 'Usage: answerback-mail.rb [-e|--email email] '
  opts.banner += "[-s|--ssh-pubkey pub_key_file] [-f|--raw-email email_file]\n"
  opts.banner += "       -e or -f is required\n"
  opts.banner += '       -s is optional when use -e'

  opts.separator ''
  opts.separator 'options:'

  opts.on('-e email_address', '--email email_address', 'appoint email address') do |email_address|
    my_info['my_email'] = email_address
    # when apply account with email address, will get no user name
    my_info['my_name'] = ''
  end

  opts.on('-s pub_key_file', '--ssh-pubkey pub_key_file', \
          'ssh pub_key file, enable password-less login') do |pub_key_file|
    my_info['my_ssh_pubkey'] = File.read(pub_key_file)
  end

  opts.on('-f email_file', '--raw-email email_file', 'email file') do |email_file|
    init_info(email_file, my_info)
  end

  opts.on_tail('-h', '--help', 'show this message') do
    puts opts
    exit
  end
end

options.parse!(ARGV)

def build_message(email, account_info)
  message = <<~EMAIL_MESSAGE
    To: #{email}
    Subject: [compass-ci] jumper account is ready

    Dear user:

      Thank you for joining us.
      You can use the following command to login the jumper server:

      Login command:
        ssh -p #{account_info['jumper_port']} #{account_info['my_login_name']}@#{account_info['jumper_host']}

      Account password:
        #{account_info['my_password']}

      Suggest:
        If you use the password to login, change it in time.

    regards
    compass-ci
  EMAIL_MESSAGE

  return message
end

def apply_account(my_info)
  account_info_str = %x(curl -XGET '#{JUMPER_HOST}:#{JUMPER_PORT}/assign_account' -d '#{my_info.to_json}')
  JSON.parse account_info_str
end

def send_account(my_info)
  message = "No email address specified\n"
  message += "use -e to add a email address\n"
  message += 'or use -f to add a email file'
  raise message if my_info['my_email'].nil?

  account_info = apply_account(my_info)
  # for manually assign account, there will be no my_commit_url
  # but the key my_commit_url is required for es
  my_info['my_commit_url'] = ''
  my_info['my_login_name'] = account_info['my_login_name']
  my_info.delete 'my_ssh_pubkey'
  store_account_info(my_info)
  message = build_message(my_info['my_email'], account_info)

  %x(curl -XPOST '#{SEND_MAIL_HOST}:#{SEND_MAIL_PORT}/send_mail_text' -d "#{message}")
end

def store_account_info(my_info)
  es = ESClient.new(index: 'accounts')
  es.put_source_by_id(my_info['my_email'], my_info)
end

send_account(my_info)
