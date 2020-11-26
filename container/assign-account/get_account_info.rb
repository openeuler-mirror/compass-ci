#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

=begin

ACCOUNT_DIR dir layout:
tree
|-- assigned-users
|   |-- user1
|   |-- user2
|   |-- user3
|   |-- ...
|-- available-users
|   |-- user11
|   |-- user12
|   |-- user13
|   |-- ...
|-- jumper-info

assigned-users: store assigned user files
available-users: store available user files
  user file name is the username
  the file content is user's password
jumper-info: store jumper server ip:port for the service

API:

call graph:
setup_jumper_account_info
  read account
    read_account_info
      build_account_info
    reread_account_info
  read_jumper_info
  config_default_yaml
  config_authorized_key
  permit_login_config
  generate_ssh_key

the returned data for setup_jumper_account_info like:
{
  "my_login_name" => "login_name",
  "password" => "password",
  "jumper_host" => "0.0.0.0",
  "jumper_port" => "10000",
  "my_jumper_pubkey" => my_jumper_pubkey
}

=end

require 'fileutils'
require 'yaml'

# get jumper and account info
class AccountStorage
  ACCOUNT_DIR = '/opt/account_data/'

  def initialize(data)
    @account_dir = ACCOUNT_DIR
    @data = data
  end

  def read_account_info
    available_dir = File.join(@account_dir, 'available-users')
    files = Dir.open(available_dir).to_a
    files -= ['.', '..']

    message = 'no more available users'
    raise message if files.empty?

    account_info = build_account_name(available_dir, files)

    return account_info
  end

  def build_account_name(available_dir, files)
    files.sort
    account_info = []
    account_info.push files[0]
    source_file = File.join(available_dir, files[0])
    account_info.push File.readlines(source_file)[0].chomp

    dest_dir = File.join(@account_dir, 'assigned-users')
    FileUtils.mv(source_file, dest_dir)

    return account_info
  end

  def read_jumper_info
    jumper_file = File.join(@account_dir, 'jumper-info')

    raise "#{jumper_file} not exist" unless File.exist? jumper_file
    raise "#{jumper_file} empty" if File.empty? jumper_file

    jumper_info = File.read(jumper_file).split(/\n/)[0].split(':')

    return jumper_info
  end

  def setup_jumper_account_info
    if @data.key?('is_update_account') && @data['is_update_account']
      login_name = @data['my_login_name']
      password = reread_account_info
    else
      login_name, password = read_account_info
    end

    jumper_host, jumper_port = read_jumper_info

    config_authorized_key(login_name)
    config_default_yaml(login_name)
    permit_login_config(login_name)
    if @data.key?('gen_sshkey') && @data['gen_sshkey']
      my_jumper_pubkey = generate_ssh_key(login_name)
    end

    jumper_account_info = {
      'my_login_name' => login_name,
      'my_password' => password,
      'jumper_host' => jumper_host,
      'jumper_port' => jumper_port,
      'my_jumper_pubkey' => my_jumper_pubkey
    }

    return jumper_account_info
  end

  def permit_login_config(login_name)
    if @data.key?('enable_login') && @data['enable_login']
      %x(usermod -s /usr/bin/zsh #{login_name})
    else
      %x(usermod -s /sbin/nologin #{login_name})
    end
  end

  def generate_ssh_key(login_name)
    ssh_dir = File.join('/home/', login_name, '.ssh')
    Dir.mkdir ssh_dir, 0o700 unless File.exist? ssh_dir
    pub_key_file = File.join(ssh_dir, 'id_rsa.pub')

    return if File.exist?(pub_key_file) && \
              @data['my_ssh_pubkey'].include?(File.read(pub_key_file).strip)

    %x(ssh-keygen -f "#{ssh_dir}/id_rsa" -N '' -C "#{login_name}@account-vm")

    FileUtils.chown_R(login_name, login_name, ssh_dir)
    File.read("/home/#{login_name}/.ssh/id_rsa.pub").strip
  end

  def touch_default_yaml(login_name)
    default_yaml_dir = File.join('/home', login_name, '.config/compass-ci/defaults')
    FileUtils.mkdir_p default_yaml_dir unless File.exist? default_yaml_dir

    default_yaml = File.join(default_yaml_dir, 'account.yaml')
    FileUtils.touch default_yaml unless File.exist? default_yaml
    default_yaml
  end

  def config_default_yaml(login_name)
    default_yaml = touch_default_yaml(login_name)

    account_yaml = YAML.load_file(default_yaml) || {}
    # my_email, my_name, my_uuid is required to config default yaml file
    # they are added along with 'my_ssh_pubkey' when sending assign account request
    account_yaml['my_email'] = @data['my_email']
    account_yaml['my_name'] = @data['my_name']
    account_yaml['my_uuid'] = @data['my_uuid']

    f = File.new(default_yaml, 'w')
    f.puts account_yaml.to_yaml
    f.close
    FileUtils.chown_R(login_name, login_name, "/home/#{login_name}/.config")
  end

  def config_authorized_key(login_name)
    pub_key = @data['my_ssh_pubkey'][0]

    return if pub_key.nil?
    return if pub_key.strip.end_with?('account-vm')

    ssh_dir = File.join('/home/', login_name, '.ssh')
    Dir.mkdir ssh_dir, 0o700 unless File.exist? ssh_dir

    authorized_file = File.join(ssh_dir, 'authorized_keys')
    FileUtils.touch authorized_file unless File.exist? authorized_file

    store_pubkey(ssh_dir, login_name, authorized_file, pub_key)
  end

  def store_pubkey(ssh_dir, login_name, authorized_file, pub_key)
    authorized_keys = File.read(authorized_file).split("\n")

    return if authorized_keys.include?(pub_key.strip)

    f = File.new(authorized_file, 'a')
    f.puts pub_key
    f.close

    FileUtils.chown_R(login_name, login_name, ssh_dir)
    File.chmod 0o600, authorized_file
  end

  def reread_account_info
    my_login_name_file = File.join(@account_dir, 'assigned-users', @data['my_login_name'])

    message = "No such assigned account exists: #{my_login_name_file}."
    raise message unless File.exist? my_login_name_file

    password = File.readlines(my_login_name_file)[0].chomp

    return password
  end
end
