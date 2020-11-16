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
  read_account_info
    build_account_name
  read_jumper_info
  config_default_yaml
  config_authorized_key
  generate_ssh_key

the returned data for setup_jumper_account_info like:
{
  "my_login_name" => "login_name",
  "password" => "password",
  "jumper_host" => "0.0.0.0",
  "jumper_port" => "10000"
}

=end

require 'fileutils'

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
    login_name, password = read_account_info
    jumper_host, jumper_port = read_jumper_info
    pub_key = @data['my_ssh_pubkey'][0]

    ssh_dir = File.join('/home/', login_name, '.ssh')
    config_authorized_key(login_name, pub_key, ssh_dir) unless pub_key.nil?
    config_default_yaml(login_name)
    my_jumper_pubkey = generate_ssh_key(login_name, ssh_dir) if @data['gen_sshkey'].eql? true

    jumper_account_info = {
      'my_login_name' => login_name,
      'my_password' => password,
      'jumper_host' => jumper_host,
      'jumper_port' => jumper_port,
      'my_jumper_pubkey' => my_jumper_pubkey
    }

    return jumper_account_info
  end

  def generate_ssh_key(login_name, ssh_dir)
    Dir.mkdir ssh_dir, 0o700 unless File.exist? ssh_dir
    %x(ssh-keygen -f "#{ssh_dir}/id_rsa" -N '' -C "#{login_name}@account-vm")
    %x(chown -R #{login_name}:#{login_name} #{ssh_dir})
    File.read("/home/#{login_name}/.ssh/id_rsa.pub")
  end

  def config_default_yaml(login_name)
    default_yaml_dir = File.join('/home', login_name, '.config/compass-ci/defaults')
    FileUtils.mkdir_p default_yaml_dir

    # my_email, my_name, my_uuid is required to config default yaml file
    # they are added along with 'my_ssh_pubkey' when sending assign account request
    File.open("#{default_yaml_dir}/account.yaml", 'a') do |file|
      file.puts "my_email: #{@data['my_email']}"
      file.puts "my_name: #{@data['my_name']}"
      file.puts "my_uuid: #{@data['my_uuid']}"
    end
    %x(chown -R #{login_name}:#{login_name} "/home/#{login_name}/.config")
  end

  def config_authorized_key(login_name, pub_key, ssh_dir)
    Dir.mkdir ssh_dir, 0o700
    Dir.chdir ssh_dir
    f = File.new('authorized_keys', 'w')
    f.puts pub_key
    f.close
    File.chmod 0o600, 'authorized_keys'
    %x(chown -R #{login_name}:#{login_name} #{ssh_dir})
  end
end
