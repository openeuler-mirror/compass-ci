# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require_relative './es_query.rb'
require_relative './params_group'
require_relative './constants.rb'
require 'elasticsearch'

def get_install_rpm_result_by_group_id(group_id)
  es = ESQuery.new
  job_list = es.multi_field_scroll_query(group_id)
  job_list.map! do |job|
    next unless job_is_useful?(job)

    tmp_hash = {}
    tmp_hash['rpm_name'] = job['_source']['rpm_name']
    key = job['_source']['rpm_name']
    tmp_hash[key] = {}
    srv_http_result_host = job['SRV_HTTP_RESULT_HOST'] || 'api.compass-ci.openeuler.org'
    srv_http_protocol = job['SRV_HTTP_PROTOCOL'] || 'https'
    tmp_hash[key]['result_url'] = "#{srv_http_protocol}://#{srv_http_result_host}#{job['_source']['result_root']}"
    tmp_hash[key]['result_root'] = "/srv#{job['_source']['result_root']}"
    tmp_hash[key]['arch'] = job['_source']['arch']
    tmp_hash[key]['property'] = job['_source']['property'] || 'Open Source'
    tmp_hash[key]['os'] = "#{job['_source']['os']} #{job['_source']['os_version']}"
    job['_source']['stats'].merge!(tmp_hash)
  end

  job_list.compact
end

def parse_rpm_name(tmp_hash, result)
  rpm_name = result['rpm_name']
  rpm_name_list = rpm_name.split(' ')
  rpm_name_list.each do |rpm_name|
    tmp_hash[rpm_name] = {} unless tmp_hash.key?(rpm_name)
    tmp_hash[rpm_name].merge!(result[result['rpm_name']])
    if rpm_name =~ /(.*)(-[^-]+){2}/
      tmp_hash[$1] = tmp_hash[rpm_name]
      tmp_hash.delete(rpm_name)
    end
  end
  tmp_hash
end

def parse_install_rpm_result_to_json(result_list)
  tmp_hash = {}
  result_list.each do |result|
    result.each do |k, v|
      case k
        # install-rpm.CUnit_rpm_full_name.CUnit-2.1.3.aarch64
      when /install-rpm\.(.*)_rpm_full_name\.(.*)/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'rpm_full_name' => $2 })
        # install-rpm.CUnit_rpm_src_name.CUnit-2.1.3-21.oe1.src.rpm
      when /install-rpm\.(.*)_rpm_src_name\.(.*)/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'rpm_src_name' => $2 })
        # install-rpm.docker-engine_install.pass
      when /install-rpm\.(.*)_install\.(.*)/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'install' => $2 })
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_uninstall.pass
      when /install-rpm\.(.*)_uninstall\.(.*)/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'uninstall' => $2 })
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_group_.Tools/Docker
      when /install-rpm\.(.*)_group_\.(.*)/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'group' => $2 })
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_libs_.true
      when /install-rpm\.(.*)_libs_\.(.*)/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'libs' => $2 })
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_bin_.pass
      when /install-rpm\.(.*)_bin_(.*)/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'bin' => $2 })
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_cmd_/usr/bin/docker.pass
      when /install-rpm\.(.*)_cmd_(.*)\.(.*)/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1]['cmds'] = {} unless tmp_hash[$1].key?('cmds')
        tmp_hash[$1]['cmds'].merge!({ $2 => $3 })
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_service_docker.service_stop.pass
      when /install-rpm\.(.*)_service_(.*)\.(.*)/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1]['services'] = {} unless tmp_hash[$1].key?('services')
        tmp_hash[$1]['services'].merge!({ $2 => $3 })
      when /^install-rpm\.(.*)_src_rpm_location\.element/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'src_location' => v })
      when /^install-rpm\.(.*)_location\.element/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'location' => v })
      when /install-rpm\.(.*)_evr.element/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'evr' => v })
      when /install-rpm\.(.*)_license.element/
        tmp_hash[$1] = {} unless tmp_hash.key?($1)
        tmp_hash[$1].merge!({ 'license' => v })
      end
    end
    tmp_hash = parse_rpm_name(tmp_hash, result)
  end

  tmp_hash
end
