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
require_relative 'build-update-email'

names = Set.new %w[
  JUMPER_HOST
  JUMPER_PORT
  SEND_MAIL_HOST
  SEND_MAIL_PORT
]

defaults = relevant_defaults(names)

JUMPER_HOST = defaults['JUMPER_HOST']
JUMPER_PORT = defaults['JUMPER_PORT'] || 29999
SEND_MAIL_HOST = defaults['SEND_MAIL_HOST'] || 'localhost'
SEND_MAIL_PORT = defaults['SEND_MAIL_PORT'] || 49000

my_info = {
  'my_email' => nil,
  'my_name' => nil,
  'my_commit_url' => nil,
  'my_uuid' => nil,
  'my_login_name' => nil,
  'my_ssh_pubkey' => []
}

# stdin_info is used to store infos added with option:
# -e email_address
# -n name
# -s pubkey_file
# email_info is used to store infos parsed from email_file with option:
# -f email_file
# my_info_es is used to store info read from ES when update user
# when use --update option
# stdin_info, email_info, my_info_es have different priority
#   stdin_info > email_info > my_info_es
# when assigning account or update conf for account
# if they have the same key, my_info will use the value with higher priority.
# conf_info is used to store keys used to config the account
stdin_info = {}
email_info = {}
my_info_es = {}
conf_info = {
  'gen_sshkey' => false,
  'enable_login' => true,
  'is_update_account' => false
}

def init_info(mail_content, email_info, my_info)
  my_info['my_email'] = mail_content.from[0]
  email_info['my_name'] = mail_content.From.unparsed_value.gsub(/ <[^<>]*>/, '')
  return if mail_content.attachments.empty?

  email_info['new_email_pubkey'] = mail_content.attachments[0].body.decoded.strip
end

def read_my_login_name(my_email, my_info_es)
  my_account_info_str = %x(curl -XGET localhost:9200/accounts/_doc/#{my_email})
  my_account_info = YAML.safe_load my_account_info_str
  message = "No such email found from the ES: #{my_email}"
  raise message unless my_account_info['found']

  my_info_es.update my_account_info['_source']
end

options = OptionParser.new do |opts|
  opts.banner = 'Usage: answerback-mail.rb [-e|--email email] [-n|--name name] '
  opts.banner += "[-s|--ssh-pubkey pub_key_file] [-g|--gen-sshkey] [-l|--login y|n] [-u|--update]\n"
  opts.banner += '       answerback-mail.rb [-f|--raw-email email_file] '
  opts.banner += "[-g|--gen-sshkey] [--login y|n] [--update]\n"
  opts.banner += "       -e|-f is required when applying account or updating account\n"
  opts.banner += "       -n is required when assigning account with -e\n"
  opts.banner += "       -s is optional when use -e\n"
  opts.banner += "       -g is optional, used to generate sshkey for user\n"
  opts.banner += "       -u is required when updating an account\n"
  opts.banner += '       -l is optional, used to enable/disable login permission'

  opts.separator ''
  opts.separator 'options:'

  opts.on('-e email_address', '--email email_address', 'appoint email address') do |email_address|
    unless email_address =~ /[^@]+@[\d\w]+\.[\w\d]+/
      message = "Not a standard format email: #{email_address}.\n\n"
      puts message

      return false
    end

    my_info['my_email'] = email_address
  end

  opts.on('-n name', '--name name', 'appoint name') do |name|
    unless name =~ /^\w[\w\d ]+/
      message = "Name should only contains letters, digits and spaces\n\n"
      puts message

      return false
    end

    stdin_info['my_name'] = name
  end

  opts.on('-s pub_key_file', '--ssh-pubkey pub_key_file', \
          'ssh pub_key file, enable password-less login') do |pub_key_file|
    unless File.exist? pub_key_file
      message = "File not found: #{pub_key_file}.\n\n"
      puts message

      return false
    end
    stdin_info['new_ssh_pubkey'] = File.read(pub_key_file).strip
  end

  opts.on('-f email_file', '--raw-email email_file', 'email file') do |email_file|
    unless File.exist? email_file
      message = "Email file not found: #{email_file}.\n\n"
      puts message

      return false
    end
    mail_content = Mail.read(email_file)
    init_info(mail_content, email_info, my_info)
  end

  opts.on('-g', '--gen-sshkey', 'generate jumper rsa public/private key and return pubkey') do
    conf_info['gen_sshkey'] = true
  end

  opts.on('-u', '--update', 'updata configurations') do
    read_my_login_name(my_info['my_email'], my_info_es)
    conf_info['is_update_account'] = true
  end

  opts.on('-l value', '--login value', 'enable/disable login, value: y|n') do |value|
    case value
    when 'y', 'Y'
      conf_info['enable_login'] = true
    when 'n', 'N'
      conf_info['enable_login'] = false
    else
      message = "-l: bad value #{value}, please use y|n\n\n"
      puts message

      return false
    end
  end

  opts.on_tail('-h', '--help', 'show this message') do
    puts opts
    exit
  end
end

# if no option specified, set default option '-h'
# if both '-e' and '-f' are not specified, will clear the ARGV,
# and use '-h' instead
if ARGV.empty?
  ARGV << '-h'
elsif (['-e', '-f'] - ARGV).eql? ['-e', '-f']
  ARGV.clear
  ARGV << '-h'
end
options.parse!(ARGV)

def apply_account(my_info, conf_info)
  apply_info = {}
  apply_info.update my_info
  apply_info.update conf_info

  account_info_str = %x(curl -XGET '#{JUMPER_HOST}:#{JUMPER_PORT}/assign_account' -d '#{apply_info.to_json}')
  JSON.parse account_info_str
end

def check_my_email(my_info)
  return true if my_info['my_email']

  message = "No email address specified\n"
  message += "use -e to add an email address for applying account\n"
  message += 'or use -f to add an email file'
  puts message

  return false
end

def build_my_info_from_input(my_info, email_info, my_info_es, stdin_info)
  new_email_pubkey = email_info.delete 'new_email_pubkey'
  new_stdin_pubkey = stdin_info.delete 'new_ssh_pubkey'
  new_pubkey = new_stdin_pubkey || new_email_pubkey

  my_info.update my_info_es unless my_info_es.empty?
  my_info.update email_info unless email_info.empty?
  my_info.update stdin_info unless stdin_info.empty?

  return if new_pubkey.nil?
  return if my_info['my_ssh_pubkey'].include? new_pubkey

  my_info['my_ssh_pubkey'].insert(0, new_pubkey)
end

def build_my_info_from_account_info(my_info, account_info, conf_info)
  unless account_info['my_jumper_pubkey'].nil?
    return if my_info['my_ssh_pubkey'][-1] == account_info['my_jumper_pubkey']

    my_info['my_ssh_pubkey'] << account_info['my_jumper_pubkey']
  end

  my_info['my_login_name'] = account_info['my_login_name'] unless conf_info['is_update_account']
end

def check_server
  return true if ENV['HOSTNAME'] == 'z9'

  message = 'please run the tool on z9 server'
  puts message

  return false
end

def check_my_name_exist(my_info)
  return true if my_info['my_name']

  message = 'No my_name found, please use -n to add one'
  puts message

  return false
end

def send_account(my_info, conf_info, email_info, my_info_es, stdin_info)
  return unless check_server
  return unless check_my_email(my_info)

  my_info['my_uuid'] = %x(uuidgen).chomp unless conf_info['is_update_account']
  build_my_info_from_input(my_info, email_info, my_info_es, stdin_info)

  return unless check_my_name_exist(my_info)

  account_info = apply_account(my_info, conf_info)
  build_my_info_from_account_info(my_info, account_info, conf_info)

  store_account_info(my_info)

  send_mail(my_info, account_info, conf_info)
end

def send_mail(my_info, account_info, conf_info)
  message = if conf_info['is_update_account']
              build_update_message(my_info['my_email'], account_info, conf_info)
            else
              build_message(my_info['my_email'], account_info)
            end

  %x(curl -XPOST '#{SEND_MAIL_HOST}:#{SEND_MAIL_PORT}/send_mail_text' -d "#{message}")
end

def store_account_info(my_info)
  es = ESClient.new(index: 'accounts')
  es.put_source_by_id(my_info['my_email'], my_info)
end

send_account(my_info, conf_info, email_info, my_info_es, stdin_info)
