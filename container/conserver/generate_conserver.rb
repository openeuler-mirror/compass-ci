#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'fileutils'
require 'yaml'

lab = ENV['lab']
system 'git clone file:///$CCI_REPOS/lab-$lab.git'

def generate_conserver(lab)
  return unless File.exist?('conserver-head.cf')

  FileUtils.cp('conserver-head.cf', 'conserver.cf')

  host_dir = "lab-#{lab}/hosts/"
  return unless Dir.exist?(host_dir)

  Dir.each_child(host_dir) do |host|
    ipmi_ip = YAML.load_file("#{host_dir}#{host}")['ipmi_ip']
    next if ipmi_ip.nil?

    console = <<~HEREDOC
    console #{host} {
      exec /usr/local/bin/ipmi-sol #{ipmi_ip};
    }
    HEREDOC
    File.open('conserver.cf', 'a') { |f| f << console }
  end
end

generate_conserver(lab)
