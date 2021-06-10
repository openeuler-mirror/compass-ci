#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative '../lib/es_client'
require_relative '../lib/build_my_info_client'
require 'optparse'

def build_my_info(option)
  build_my_info = BuildMyInfo.new(option['my_email'])
  info_es = build_my_info.search_my_info
  info_es.update option
  info_es['my_token'] = %x(uuidgen).chomp if info_es['my_token'].nil?
  info_es['my_ssh_pubkey'] = []

  build_my_info.config_my_info(info_es)
end

if $PROGRAM_NAME == __FILE__
  option = {
    'my_email' => `git config --global user.email`.chomp,
    'my_name' => `git config --global user.name`.chomp,
    'lab' => `awk '/^lab:\s/ {print $2; exit}' /etc/compass-ci/defaults/*.yaml`.chomp
  }

  options = OptionParser.new do |opts|
    opts.banner = "Usage: build-my-info [-e email] [-n name] [-l lab] [-t]\n"

    opts.separator ''
    opts.separator 'options:'

    opts.on('-e email', 'my_email') do |email|
      option['my_email'] = email
    end

    opts.on('-n name', 'my_name') do |name|
      option['my_name'] = name
    end

    opts.on('-l lab', 'lab') do |lab|
      option['lab'] = lab
    end

    opts.on('-t', 'my_token') do
      option['my_token'] = %x(uuidgen).chomp
    end

    opts.on_tail('-h', 'show this message') do
      puts opts
      exit
    end
  end

  options.parse!

  build_my_info(option)
end
