#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'io/console'
require_relative '../lib/es_client'

# purpose:
#         build my_info
#         store my_info to ES
#         write my_info to default/lab yaml file
# for user install compass-ci at their local server
# user meet verification problems when submit jobs
# add calling in installing script to meet the verification function
# usage:
#         require_relative 'build_my_info_client'
#
#         build_my_info = BuildMyInfo.new(email, name, lab)
#         build_my_info.config_my_info
class BuildMyInfo
  def initialize(my_email, my_name, lab, my_token = nil)
    @lab = lab || 'nolab'
    @my_token = my_token || %x(uuidgen).chomp
    @my_info = {
      'my_email' => my_email,
      'my_name' => my_name,
      'my_token' => @my_token,
      'my_login_name' => nil,
      'my_commit_url' => nil,
      'my_ssh_pubkey' => []
    }
  end

  def config_default_yaml
    default_yaml_dir = "#{ENV['HOME']}/.config/compass-ci/defaults"
    FileUtils.mkdir_p default_yaml_dir unless File.directory? default_yaml_dir
    default_yaml_file = "#{default_yaml_dir}/account.yaml"
    FileUtils.touch(default_yaml_file) unless File.exist? default_yaml_file

    default_yaml_info = YAML.load_file(default_yaml_file) || {}
    default_yaml_info['my_email'] = @my_info['my_email']
    default_yaml_info['my_name'] = @my_info['my_name']
    default_yaml_info['lab'] = @lab

    File.open(default_yaml_file, 'w') do |f|
      f.puts default_yaml_info.to_yaml
    end
  end

  def config_lab_yaml
    lab_yaml_dir = "#{ENV['HOME']}/.config/compass-ci/include/lab"
    FileUtils.mkdir_p lab_yaml_dir unless File.directory? lab_yaml_dir
    lab_yaml_file = "#{lab_yaml_dir}/#{@lab}.yaml"
    FileUtils.touch(lab_yaml_file) unless File.exist? lab_yaml_file

    lab_yaml_info = YAML.load_file(lab_yaml_file) || {}
    lab_yaml_info['my_token'] = @my_info['my_token']

    File.open(lab_yaml_file, 'w') do |f|
      f.puts lab_yaml_info.to_yaml
    end
  end

  def store_account_info
    es = ESClient.new(index: 'accounts')
    es.put_source_by_id(@my_info['my_email'], @my_info)
  end

  def config_my_info
    config_default_yaml
    config_lab_yaml
    store_account_info
  end
end
