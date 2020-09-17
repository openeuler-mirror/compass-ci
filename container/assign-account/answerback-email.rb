#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'json'
require 'mail'
require 'set'
require_relative '../defconfig.rb'

names = Set.new %w[
  JUMPER_IP
  JUMPER_PORT
  CRYSTAL_INTRANET
  SEND_MAIL_PORT
]

defaults = relevant_defaults(names)

JUMPER_IP = defaults['JUMPER_IP']
JUMPER_PORT = defaults['JUMPER_PORT']
CRYSTAL_INTRANET = defaults['CRYSTAL_INTRANET']
SEND_MAIL_PORT = defaults['SEND_MAIL_PORT']

def build_message(email, message_id, infos)
  message = <<~EMAIL_MESSAGE
    To: #{email}
    Message-ID: #{message_id}
    Subject: jumper account is ready
 
    Dear #{email}
 
      Thank you for joining us.
      You can use the following command to login the jumper server:

      login command:
        ssh -p #{infos['jumper_port']} #{infos['account']}@#{infos['jumper_ip']}

      account passwd:
        account_password: #{infos['passwd']}

    regards
    crystal-ci
  EMAIL_MESSAGE

  return message
end

def email_addr(mail_content)
  msg = 'not an applying account email'

  raise msg unless mail_content.subject =~ /apply ssh account/i

  email = mail_content.from.join(',')

  return email
end

# def check_email_available(mail_content, email)
#   url = mail_content.body.decoded.split(/\n/).find { |line| line =~ /http:\/\/|https:\/\// }
#   url_fdback = %x(curl #{url})
#   email_index = url_fdback.index email
#
#   message = 'No commit info found from the url for the email'
#   raise message unless email_index
# end

def email_message_id(mail_content)
  message_id = mail_content.message_id
  return message_id
end

def pub_key_value(mail_content)
  pub_key = mail_content.body.decoded.split(/\n/).find { |line| line =~ /ssh-rsa/ }
  return pub_key
end

def account_info(pub_key)
  account_info_str = %x(curl -XGET '#{JUMPER_IP}:#{JUMPER_PORT}/assign_account' -d "pub_key: #{pub_key}")
  account_info = JSON.parse account_info_str

  return account_info
end

def send_account(mail_content)
  email = email_addr(mail_content)
  message_id = email_message_id(mail_content)
  # check_email_available(mail_content, email)

  pub_key = pub_key_value(mail_content)
  acct_info = account_info(pub_key)

  message = build_message(email, message_id, acct_info)

  %x(curl -XPOST '#{CRYSTAL_INTRANET}:#{SEND_MAIL_PORT}/send_mail_text' -d "#{message}")
end

def read_mail_content(mail_file)
  mail_content = Mail.read(mail_file)

  return mail_content
end

mail_file = ARGV[0]
mail_content = read_mail_content(mail_file)
send_account(mail_content)
