#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'yaml'

def cci_defaults
  hash = {}
  Dir.glob(['/etc/compass-ci/defaults/*.yaml',
            '/etc/compass-ci/accounts/*.yaml',
            "#{ENV['HOME']}/.config/compass-ci/defaults/*.yaml"]).each do |file|
    hash.update YAML.load_file(file) || {}
  end
  hash
end

def relevant_defaults(names)
  cci_defaults.select { |k, _| names.include? k }
end

def set_local_env
  hash = cci_defaults
  hash.map { |k, v| system "export #{k}=#{v}" }
end

def docker_env(hash)
  hash.map { |k, v| ['-e', "#{k}=#{v}"] }.flatten
end

def docker_rm(container)
  res = %x(docker ps -aqf name="^#{container}$")
  return if res.empty?

  system "docker stop #{container} && docker rm -f #{container}"
end

def meminfo_hash
  YAML.load_file('/proc/meminfo')
end

def get_available_memory
  memtotal = meminfo_hash['MemTotal'].to_f / 1048576

  # set container available memory size, minimum size is 1024m, maximum size is 30720m,
  # take the middle value according to the system memory size.
  [1024, 30720, Math.sqrt(memtotal) * 1024].sort[1].to_i
end
