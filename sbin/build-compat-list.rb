#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

# What's purpose:
#   - The script is used to add, delete, modify, and query the software compatibility list.
# How to use:
#   cmd: build-compat-list group_id=compat-centos7 -u
#   - params: $1 Keyword and value
#   - params: $2 update the results whose group_id is compat-centos7 to es databse
#   cmd: build-compat-list -a -j or build-compat-list group_id=compat-centos7 -j
#   - params: $1 '-a' means all data in software compatibility list table
#   - params: $2 puts data in JSON format on the terminal
#   cmd: build-compat-list -a -o xxx.csv
#   - params: $2 save the data to a file in CSV format
#   cmd: build-compat-list -r xxx.csv
#   - params: $1 read data from a CSV file and updates it to the database
#   cmd: build-compat-list -d os=openEuler
#   - delete each data whose os field is openEuler

require_relative '../lib/parse_install_rpm'
require_relative '../lib/constants.rb'
require_relative '../lib/my_data.rb'
require 'json'
require 'optparse'
require 'elasticsearch'
require 'csv'

def puts_json(items, option)
  result_list = get_result_list(items, option)
  result_list.each do |info|
    puts JSON.pretty_generate info
  end
end

def get_results_by_group_id(items, option)
  query = { 'group_id' => items['group_id'] || option['group_id'] }
  tmp_stats_hash = get_install_rpm_result_by_group_id(query)
  stats_hash = parse_install_rpm_result_to_json(tmp_stats_hash)
  refine_json(stats_hash)
end

def get_result_list(items, option)
  if option['all_data']
    result_list = get_all_data
    result_list.map! do |info|
      info['_source']
    end
    result_list.compact
  else
    result_list = get_results_by_group_id(items, option)
  end
end

def get_all_data
  my_data = MyData.new

  body = {
    "query": {
      "match_all": {}
    }
  }

  my_data.es_search_all('compat-software-info', body)
end

def update_compat_software?(index, query, info)
  my_data = MyData.new
  data = my_data.es_query(index, query)
  _id = "#{info['softwareName']}--#{info['version']}--#{info['arch']}--#{info['os']}"
  add = my_data.es_add(index, _id, info.to_json) if data['took'] == 0
  data['hits']['hits'].each do |source|
    my_data.es_delete(index, source['_id']) unless source['_source']['install'] == 'pass'
    my_data.es_delete(index, source['_id']) unless source['_source'].key?('bin')
    my_data.es_delete(index, source['_id']) if source['_source']['delete']

    if source['_id'] == _id
      id = source['_id']
      my_data.es_update(index, id, info)
    else
      my_data.es_add(index, _id, info.to_json)
    end
  end
  sleep 2
end

def read_csv_file(filename)
  CSV.foreach(filename, liberal_parsing: true, headers: :first_row) do |row|
    data = row.to_h
    data['license'] = data['license'].gsub('/', ',') || data['license']
    data['src_location'] = JSON.parse(data['src_loaction'].split) if data['src_loaction']
    data['cmds'] = JSON.parse(data['cmds'].split.join(',')) if data['cmds']
    query = {
      'query' => {
        'query_string' => {
          'query' => "softwareName:#{data['softwareName']}"
        }
      }
    }.to_json
    update_compat_software?('compat-software-info', query, data)
  end
end

def save_to_csv(items, option)
  result_list = get_result_list(items, option)
  File.open((option['output']).to_s, 'w') do |f|
    header = 'os,arch,property,result_url,result_root,bin,uninstall,license,libs,install,'
    header += 'src_location,group,cmds,type,softwareName,category,version,downloadLink'
    f.puts header
    result_list.each do |info|
      if info.key?('cmds') && info['cmds']
        cmds = info['cmds'].to_json.gsub!(',', ' ') || info['cmds'].to_json
      end
      if info.key?('src_location') && info['src_location']
        src_location = info['src_location'].to_json.gsub!(',', ' ') || info['src_location']
      end
      license = info['license'].gsub(',', '/') || info['license']
      line = "#{info['os']},#{info['arch']},#{info['property']},#{info['result_url']},"
      line += "#{info['result_root']},#{info['bin']},#{info['uninstall']},#{license},#{info['libs']},"
      line += "#{info['install']},#{src_location},#{info['group']},#{cmds},#{info['type']},"
      line += "#{info['softwareName']},#{info['category']},#{info['version']},#{info['downloadLink']}"
      f.puts line
    end
  end
end

def dump_to_es(items, option)
  result_list = get_result_list(items, option)
  result_list.each do |info|
    next unless info['install'] == 'pass'
    next unless info.key?('bin')

    query = {
      'query' => {
        'query_string' => {
          'query' => "softwareName:#{info['softwareName']}"
        }
      }
    }.to_json
    update_compat_software?('compat-software-info', query, info)
  end
end

def delete_data(option)
  my_data = MyData.new
  result_list = get_all_data
  result_list.each do |source|
    info = source['_source']
    key, value = option['delete_data'].split('=')
    next unless key

    value_list = value.split(',')
    if value_list.length > 1
      value_list.each do |value|
        if info.key?(key) && info[key] == value
          my_data.es_delete('compat-software-info', source['_id'])
        end
      end
    elsif info.key?(key) && info[key] == value
      my_data.es_delete('compat-software-info', source['_id'])
    end
  end
end

def query_location(version, field, pkg_info)
  location = ''
  if pkg_info.key?(field)
    unless pkg_info[field].empty?
      pkg_info[field].each do |loc|
        location = loc if loc.include?(version)
      end
    end
  end
  location
end

def libs_or_cmds(_version, pkg_info)
  category = []
  category << 'bin' if pkg_info.key?('bin')
  category << 'lib' if pkg_info['libs'] == 'true'
  category = category.join('/') unless category.empty?
end

def refine_json(data)
  result_list = []
  data.each_key do |pkg|
    pkg_info = data[pkg]
    next unless pkg_info['evr']

    pkg_info['evr'].each do |version|
      tmp_hash = {}
      tmp_hash.merge!({ 'os' => pkg_info['os'], 'arch' => pkg_info['arch'] })
      tmp_hash.merge!({ 'property' => pkg_info['property'], 'result_url' => pkg_info['result_url'] })
      tmp_hash.merge!(pkg_info).delete('evr')
      tmp_hash.delete('location')
      tmp_hash.delete('src_location')
      version = version.split(':')[-1]
      category = libs_or_cmds(version, pkg_info)
      location = query_location(version, 'location', pkg_info)
      src_location = query_location(version, 'src_location', pkg_info)
      next unless location.start_with?('https://api.compass-ci.openeuler.org:20018')
      next unless src_location.start_with?('https://api.compass-ci.openeuler.org:20018')

      tmp_hash['type'] = pkg_info['group']
      tmp_hash['softwareName'] = pkg
      tmp_hash['category'] = category
      tmp_hash['version'] = version
      tmp_hash['downloadLink'] = location
      tmp_hash['src_location'] = src_location
      tmp_hash['license'] = pkg_info['license'][0] if pkg_info['license']
      tmp_hash['install'] = pkg_info['install']
      result_list << tmp_hash
    end
  end
  result_list
end

def parse_argv
  items = {}
  ARGV.each do |item|
    key, value = item.split('=')
    if key && value
      value_list = value.split(',')
      items[key] = value_list.length > 1 ? value_list : value
    end
  end
  items
end

if $PROGRAM_NAME == __FILE__
  option = {}

  options = OptionParser.new do |opts|
    opts.banner = "Usage: build-compat-list [options] [group_id]\n"
    opts.banner += "examples: build-compat-list group_id=compat-centos7 -u\n"

    opts.separator ''
    opts.separator 'options:'

    opts.on('-u', 'update the es database') do
      option['group_id'] = Time.new.strftime('%Y-%m-%d') + '-auto-install-rpm'
      option['update_es'] = true
    end

    opts.on('-o output_file', 'save the data to output_file in CSV format') do |file|
      option['group_id'] = Time.new.strftime('%Y-%m-%d') + '-auto-install-rpm'
      option['output'] = file
    end

    opts.on('-r refresh es db', 'read data from a CSV file and updates it to the database') do |csv|
      option['csv_file'] = csv
    end

    opts.on('-j', 'puts data in JSON format on the terminal') do
      option['group_id'] = Time.new.strftime('%Y-%m-%d') + '-auto-install-rpm'
      option['json_format'] = true
    end

    opts.on('-a', 'all data') do
      option['all_data'] = true
    end

    opts.on('-d delete_field', 'specified delete data field') do |dimension|
      option['delete_data'] = dimension
    end

    opts.on_tail('-h', 'show this message') do
      puts opts
      exit
    end
  end

  options.parse!(ARGV)
  items = parse_argv

  if option['update_es']
    dump_to_es(items, option)
  end

  if option['delete_data']
    delete_data(option)
  end

  if option['json_format']
    puts_json(items, option)
  end

  if option['output']
    save_to_csv(items, option)
  end

  if option['csv_file']
    read_csv_file(option['csv_file'])
  end

  if items.empty? && option.empty?
    puts(options)
    exit
   end
end
