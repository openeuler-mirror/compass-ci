#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative '../lib/es_client'
require_relative '../lib/build_my_info_client'
require 'optparse'

option = {
  my_name: `git config --global user.name`.chomp,
  my_email: `git config --global user.email`.chomp,
  lab: `awk '/^lab:\s/ {print $2; exit}' /etc/compass-ci/defaults/*.yaml`.chomp
}

options = OptionParser.new do |opts|
  opts.on('-e email', 'my_email') do |email|
    option[:email] = email
  end

  opts.on('-n name', 'my_name') do |name|
    option[:name] = name
  end

  opts.on('-l lab', 'lab') do |lab|
    option[:lab] = lab
  end
end

options.parse!

build_my_info = BuildMyInfo.new(option[:my_email], option[:my_name], option[:lab])
build_my_info.config_my_info
