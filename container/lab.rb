#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'yaml'

def cci_defaults
  hash = {}
  Dir.glob(['/etc/crystal-ci/defaults/*.yaml',
            "#{ENV['HOME']}/.config/crystal-ci/defaults/*.yaml"]).each do |file|
    hash.update YAML.load_file(file)
  end
  hash
end

def relevant_defaults(names)
  cci_defaults.select { |k, _| names.include? k }
end

def docker_env(hash)
  hash.map { |k, v| ['-e', "#{k}=#{v}"] }.flatten
end
