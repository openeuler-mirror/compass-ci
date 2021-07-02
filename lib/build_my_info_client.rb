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
#         build_my_info = BuildMyInfo.new(my_info['email'])
#         build_my_info.config_my_info(my_info)
class BuildMyInfo
  def initialize(my_email)
    @my_email = my_email
    @es = ESClient.new(index: 'accounts')
  end

  def search_my_info
    @es.query_by_id(@my_email) || {}
  end

  def store_account_info(my_info)
    @es.put_source_by_id(@my_email, my_info)
  end

  def config_default_yaml(my_info)
    default_yaml_dir = "#{ENV['HOME']}/.config/compass-ci/defaults"
    FileUtils.mkdir_p default_yaml_dir unless File.directory? default_yaml_dir
    default_yaml_file = "#{default_yaml_dir}/account.yaml"
    FileUtils.touch(default_yaml_file) unless File.exist? default_yaml_file

    default_yaml_info = YAML.load_file(default_yaml_file) || {}
    default_yaml_info['my_email'] = my_info['my_email']
    default_yaml_info['my_name'] = my_info['my_name']
    default_yaml_info['my_account'] = my_info['my_account']
    default_yaml_info['lab'] = my_info['lab']

    File.open(default_yaml_file, 'w') do |f|
      f.puts default_yaml_info.to_yaml
    end
  end

  def config_lab_yaml(my_info)
    lab_yaml_dir = "#{ENV['HOME']}/.config/compass-ci/include/lab"
    FileUtils.mkdir_p lab_yaml_dir unless File.directory? lab_yaml_dir
    lab_yaml_file = "#{lab_yaml_dir}/#{my_info['lab']}.yaml"
    FileUtils.touch(lab_yaml_file) unless File.exist? lab_yaml_file

    lab_yaml_info = YAML.load_file(lab_yaml_file) || {}
    lab_yaml_info['my_token'] = my_info['my_token']

    File.open(lab_yaml_file, 'w') do |f|
      f.puts lab_yaml_info.to_yaml
    end
  end

  # when update/add item that with a unique attribute, 
  # we need to check if the item already exists.
  def check_item_unique(email, key, value)
    doc = @es.multi_field_query({ key => value }, single_index: true)['hits']['hits']
    return true if doc.empty?

    return false if doc.size > 1

    doc[0]['_source']['my_email'] == email
  end

  def config_my_info(my_info)
    store_account_info(my_info)
    config_default_yaml(my_info)
    config_lab_yaml(my_info)
  end
end
