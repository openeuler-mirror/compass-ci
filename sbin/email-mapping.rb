#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'yaml'
require 'optparse'
require '../container/defconfig'

config = cci_defaults
REDIS_HOST ||= ENV['REDIS_HOST'] ||= config['REDIS_HOST'] || 'localhost'
REDIS_PORT ||= ENV['REDIS_PORT'] ||= config['REDIS_PORT'] || '6379'

# require_relative "#{ENV['CCI_SRC']}/lib/redis_client"
require '../lib/redis_client'

r_name = nil
d_email = nil
file_email_mapping = {}
map_conf = {
  're_mapping' => false,
  'del_map' => false,
  'search_map' => false,
  'delete_queue' => false,
  'search_all_map' => false
}

options = OptionParser.new do |opts|
  opts.banner = "Usage: email_mapping -n name [-e email_address] [-d] [-s] [-r]\n"
  opts.banner += "       email_mapping -f mapping_file [-r] [-d] [-s]\n"
  opts.banner += "       email_mapping --delete-queue\n"
  opts.banner += "       email_mapping --search-all\n"

  opts.separator ''
  opts.separator 'options:'

  opts.on('-n name|email|tag', '--name name|email|tag', 'appoint a name|email|tag to add mapping') do |name|
    r_name = name
  end

  opts.on('-e email_address', '--email email_address', 'appoint a email to be mapped') do |email|
    d_email = email
  end

  opts.on('-f filename', '--file filename', 'appoint a mapping file for name/email') do |filename|
    mapping_content = YAML.load_file(filename) || {}
    file_email_mapping.update mapping_content
  end

  opts.on('-r', '--re-map', 'do re-mappings') do
    map_conf['re_mapping'] = true
  end

  opts.on('-d', '--delete', 'delete email mappings') do
    map_conf['del_map'] = true
  end

  opts.on('--delete-queue', 'delete mapping queue') do
    map_conf['delete_queue'] = true
  end

  opts.on('-s', '--search', 'search email mapping') do
    map_conf['search_map'] = true
  end

  opts.on('--search-all', 'search all email mappings') do
    map_conf['search_all_map'] = true
  end

  opts.on_tail('-h', '--help', 'show this message') do
    puts opts
    exit
  end
end

required_opts = ['-n', '-f', '--delete-queue', '--search-all']

if ARGV.empty?
  ARGV << '-h'
elsif (required_opts - ARGV).eql? required_opts
  ARGV.clear
  ARGV << '-h'
end

options.parse!(ARGV)

def email_mapping(r_name, d_email, map_conf)
  email_mapping = RedisClient.new('email_mapping')
  if map_conf['re_mapping']
    email_mapping.reset_hash_key(r_name, d_email)
  elsif map_conf['del_map']
    email_mapping.delete_hash_key(r_name)
  elsif map_conf['search_map']
    mapped_email = email_mapping.search_hash_key(r_name)
    if mapped_email.nil? || mapped_email.empty?
      puts "#{r_name} has not been mapped an email yet."
    else
      puts mapped_email
    end
  elsif map_conf['search_all_map']
    all_mappings = email_mapping.search_all_hash_key

    all_mappings.each do |k, v|
      puts "#{k}: #{v}\n"
    end
  elsif map_conf['delete_queue']
    email_mapping.delete_queue
  else
    return if email_mapping.add_hash_key(r_name, d_email)

    puts "#{r_name} has already mapped an email."
  end
end

if file_email_mapping.empty?
  email_mapping(r_name, d_email, map_conf)
else
  file_email_mapping.each do |name, email|
    email_mapping(name, email, map_conf)
  end
end
