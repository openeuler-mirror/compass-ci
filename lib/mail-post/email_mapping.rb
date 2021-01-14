#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'redis'

# email address translation according to the email_mapping queue.
# email_mapping is used to set email mapping, example:
# email_mapping:
#   name => email_address_d
#   tag => email_address_d
#   email_address_r => email_address_d
#   ...
#
# can set multi keys for an email address, the key can be a name,
# an email, or some something else like a tag.
# case add the key is added to email address bar, the key will be
# transferred to the mapped email address.
class EmailAddrMapping
  def initialize(mail_info)
    @mail_info = mail_info
    @redis = Redis.new('host' => REDIS_HOST, 'port' => REDIS_PORT)
  end

  def check_email_mapping
    email_to = @mail_info['to'].clone
    email_cc = @mail_info['cc'].clone
    email_bcc = @mail_info['bcc'].clone
    @mail_info['to'] = email_mapping(email_to)
    @mail_info['cc'] = email_mapping(email_cc)
    @mail_info['bcc'] = email_mapping(email_bcc)

    return @mail_info
  end

  def email_mapping(mail_list)
    return if mail_list.nil? || mail_list.empty?

    mail_list.clone.each do |email|
      next unless @redis.hexists 'email_mapping', email

      mapped_email = @redis.hget 'email_mapping', email
      mail_list -= [email]
      mail_list << mapped_email unless mail_list.include? mapped_email
    end
    return mail_list
  end
end
