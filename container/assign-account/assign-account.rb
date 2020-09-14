#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'sinatra'
require 'open3'
require 'json'
require 'yaml'

set :bind, '0.0.0.0'
set :port, 29999

get '/assign_account' do
  begin
    data = YAML.safe_load request.body.read
  rescue StandardError => e
    puts e.message
  end
  pub_key = data['pub_key'] if data.key? 'pub_key'
  account_dir = '/data/'
  cache_user = read_account_info(account_dir)
  jumper_info = read_jumper_info(account_dir)

  account_info = set_up_account_info(cache_user, jumper_info, pub_key)
  return account_info.to_json
end

def set_up_account_info(cache_user, jumper_info, pub_key)
  jmp_ip      = jumper_info[0].chomp
  jmp_pt      = jumper_info[1].chomp
  account     = cache_user[0].chomp
  passwd      = if pub_key
                  'Use pub_key to login'
                else
                  cache_user[1].chomp
                end

  account_info = {
    'account' => account,
    'passwd' => passwd,
    'jmp_ip' => jmp_ip,
    'jmp_pt' => jmp_pt
  }

  set_up_authorized_key(account, pub_key)
  return account_info
end

def read_account_info(file_dir)
  available_dir = file_dir + 'available-users/'
  files = Dir.open(available_dir).to_a
  files -= ['.', '..']

  message = 'no more available users'
  raise message if files.empty?

  cache_user = build_cache_user(available_dir, file_dir, files)

  return cache_user
end

def build_cache_user(available_dir, file_dir, files)
  files.sort
  cache_user = []
  cache_user.push files[0]
  source_file = available_dir + files[0]
  cache_user.push File.readlines(source_file)[0].chomp
  dest_dir = file_dir + 'assigned-users/'
  FileUtils.mv(source_file, dest_dir)

  return cache_user
end

def read_jumper_info(file_dir)
  jumper_file = file_dir + 'jumper-info'

  raise "#{jumper_file} not exist" unless File.exist? jumper_file
  raise "#{jumper_file} empty" if File.empty? jumper_file

  jumper_info = File.read(jumper_file).split(/\n/)[0].split(':')

  return jumper_info
end

def set_up_authorized_key(account, pub_key)
  ssh_dir = '/home/' + account + '/.ssh'
  Dir.mkdir ssh_dir, 700
  Dir.chdir ssh_dir
  f = File.new('authorized_keys', 'w')
  f.puts pub_key
  f.close
  File.chmod 600, 'authorized_keys'
  %x(chown -R #{account}:#{account} #{ssh_dir})
end
