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
require_relative 'build-send-account-email'

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
  'my_commit_url' => nil,
  'my_uuid' => %x(uuidgen).chomp,
  'my_ssh_pubkey' => [],
  'gen_sshkey' => false
}

def init_info(mail_content, my_info)
  my_info['my_email'] = mail_content.from[0]
  my_info['my_name'] = mail_content.From.unparsed_value.gsub(/ <[^<>]*>/, '')
  return if mail_content.attachments.empty?

  my_info['my_ssh_pubkey'] << mail_content.attachments[0].body.decoded
end

options = OptionParser.new do |opts|
  opts.banner = 'Usage: answerback-mail.rb [-e|--email email] '
  opts.banner += "[-s|--ssh-pubkey pub_key_file] [-f|--raw-email email_file] [-g|--gen-sshkey]\n"
  opts.banner += "       -e or -f is required\n"
  opts.banner += "       -s is optional when use -e\n"
  opts.banner += '       -g is optional, used to generate sshkey for user'

  opts.separator ''
  opts.separator 'options:'

  opts.on('-e email_address', '--email email_address', 'appoint email address') do |email_address|
    my_info['my_email'] = email_address
  end

  opts.on('-s pub_key_file', '--ssh-pubkey pub_key_file', \
          'ssh pub_key file, enable password-less login') do |pub_key_file|
    my_info['my_ssh_pubkey'] << File.read(pub_key_file).chomp
  end

  opts.on('-f email_file', '--raw-email email_file', 'email file') do |email_file|
    mail_content = Mail.read(email_file)
    init_info(mail_content, my_info)
  end

  opts.on('-g', '--gen-sshkey', 'generate jumper ras public/private key and return pubkey') do
    my_info['gen_sshkey'] = true
  end

  opts.on_tail('-h', '--help', 'show this message') do
    puts opts
    exit
  end
end

options.parse!(ARGV)

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
  my_info['my_login_name'] = account_info['my_login_name']

  unless account_info['my_jumper_pubkey'].nil?
    my_info['my_ssh_pubkey'] << account_info['my_jumper_pubkey'].chomp
  end

  my_info.delete 'gen_sshkey'
  store_account_info(my_info)

  send_mail(my_info, account_info)
end

def send_mail(my_info, account_info)
  message = build_message(my_info['my_email'], account_info)

  %x(curl -XPOST '#{SEND_MAIL_HOST}:#{SEND_MAIL_PORT}/send_mail_text' -d "#{message}")
end

def store_account_info(my_info)
  es = ESClient.new(index: 'accounts')
  es.put_source_by_id(my_info['my_email'], my_info)
end

send_account(my_info)
