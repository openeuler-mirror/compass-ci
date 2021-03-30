#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'redis'

# check if the emails count has beyond the limit.
# email_in_limit is used to store email address email count
# less than the limit value.
# email_out_limit is used to store email address email count
# beyond the limit.
# case the email is the first one for the day, the email will
# be add to email_in_limit with value 1.
# case the email in email_in_limit but email count less than the
# limit value, its value will +1.
# case the email's email count up to the limit value, the email
# will be moved to email_out_limit.
# when the email is in email_out_limit, if send mail to the email
# address, the email will be kicked out from the email address bar.
class EmailRateLimit
  def initialize(mail_info)
    @mail_info = mail_info
    @redis = Redis.new('host' => REDIS_HOST, 'port' => REDIS_PORT)
  end

  def check_email_counts
    email_to = @mail_info['to'].clone
    email_cc = @mail_info['cc'].clone
    @mail_info['to'] = check_emails(email_to)
    @mail_info['cc'] = check_emails(email_cc)

    return @mail_info
  end

  def check_emails(mail_list)
    return if mail_list.nil? || mail_list.empty?

    mail_list.clone.each do |email|
      if @redis.hexists 'email_out_limit', email
        mail_list -= [email]
        next
      elsif @redis.hexists 'email_in_limit', email
        email_account = @redis.hget 'email_in_limit', email
        @redis.hset 'email_in_limit', email, email_account.to_i + 1
      else
        @redis.hset 'email_in_limit', email, 1
      end

      change_queue(email)
    end
    return mail_list
  end

  def change_queue(email)
    return unless (@redis.hget 'email_in_limit', email).to_i >= ENV['EMAIL_LIMIT_COUNT'].to_i

    @redis.hdel 'email_in_limit', email
    @redis.hset 'email_out_limit', email, ENV['EMAIL_LIMIT_COUNT']
  end
end
