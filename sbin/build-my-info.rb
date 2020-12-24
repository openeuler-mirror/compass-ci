#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'io/console'
require_relative '../lib/es_client'
require_relative '../lib/build_my_info_client'

print 'email: '
my_email = $stdin.echo = gets.chomp
print 'name: '
my_name = $stdin.echo = gets.chomp
print 'lab: '
lab = $stdin.echo = gets.chomp

build_my_info = BuildMyInfo.new(my_email, my_name, lab)
build_my_info.config_my_info
