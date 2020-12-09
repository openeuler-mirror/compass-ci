#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'io/console'
require_relative '../lib/es_client'

print 'email: '
my_email = $stdin.echo = gets.chomp
print 'name: '
my_name = $stdin.echo = gets.chomp
my_uuid = %x(uuidgen).chomp

my_info = {
  'my_email' => my_email,
  'my_name' => my_name,
  'my_uuid' => my_uuid
}

def store_account_info(my_info)
  es = ESClient.new(index: 'accounts')
  es.put_source_by_id(my_info['my_email'], my_info)
end

def config_default_yaml(my_info)
  yaml_dir = "#{ENV['HOME']}/.config/compass-ci/defaults"
  FileUtils.mkdir_p yaml_dir unless File.directory? yaml_dir
  yaml_file = "#{yaml_dir}/account.yaml"
  FileUtils.touch(yaml_file) unless File.exist? yaml_file

  yaml_info = YAML.load_file(yaml_file) || {}
  yaml_info.update my_info

  File.open(yaml_file, 'w') do |f|
    f.puts yaml_info.to_yaml
  end
end

def complete_my_info(my_info)
  my_info['my_login_name'] = ''
  my_info['my_commit_url'] = ''
  my_info['my_ssh_pubkey'] = []
end

config_default_yaml(my_info)
complete_my_info(my_info)
store_account_info(my_info)
