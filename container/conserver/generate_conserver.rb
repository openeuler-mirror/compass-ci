#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'fileutils'
require 'yaml'

lab = ENV['LAB'] || 'z9'
CCI_REPOS = ENV['CCI_REPOS'] || '/c'

def generate_conserver(lab)
  return unless File.exist?('conserver-head.cf')

  FileUtils.cp('conserver-head.cf', 'conserver.cf')
  
  host_dir = "#{CCI_REPOS}/lab-#{lab}/hosts/"
  unless Dir.exist?(host_dir)
    puts "please check whether the #{host_dir} directory exists "
    return
  end

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
