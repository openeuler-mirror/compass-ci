#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'listen'
require 'mail'
require 'fileutils'
require_relative 'lib/apply-account'

MAILDIR = ENV['MAILDIR']

def monitor_new_email(mail_inbox, mail_drafts)
  listener = Listen.to(mail_inbox) do |_modified, added, _removed|
    next if added.empty?

    added.each do |mail_file|
      handle_new_email(mail_file, mail_drafts)
    end
  end
  listener.start
  sleep
end

def handle_new_email(mail_file, mail_drafts)
  mail_content = Mail.read(mail_file)
  apply_account(mail_content)

  FileUtils.mv(mail_file, mail_drafts)
end

def apply_account(mail_content)
  return unless mail_content.subject.match?(/apply account/i)

  assign_uuid = ApplyAccount.new(mail_content)
  assign_uuid.check_to_send_account
end

monitor_new_email("#{MAILDIR}/new", "#{MAILDIR}/cur")
