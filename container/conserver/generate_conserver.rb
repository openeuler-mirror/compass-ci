#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'fileutils'
require 'yaml'

lab = 'z9'
lab = 'crystal' if ENV['HOSTNAME'].include?("crystal")
CCI_REPOS = ENV['CCI_REPOS'] || '/c'

exit 1 unless File.exist?('conserver-head.cf')
FileUtils.cp('conserver-head.cf', 'conserver.cf')

def generate_conserver_by_lab(lab)
  host_dir = "#{CCI_REPOS}/lab-#{lab}/hosts/"
  puts host_dir
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

def generate_conserver_by_cfg(host_file, server_file)
  hosts = Hash.new
  servers = Hash.new

  host_ff = File.open(host_file)
  host_ff.each_line do |line|
    # line e.g.: pe-c cc-05-77-fe-cf-86 taishan200-2280-2s64p-256g--a143
    if line =~ %r|(p[^ ]*) ([^ ]*) (taishan.*)|
        num = $1.chomp
        name = $3.chomp
        hosts[num] = name
    end
  end

  server_ff = %x(awk '{print $1" "$2}' #{server_file})
  server_ff.each_line do |line|
    # line e.g.: 9.3.14.12 pe-c
    if line =~ %r|(^9[^ ]*) (p[^ ]*)|
        ip = $1.strip
        num = $2.strip
        servers[num] = ip
    end
  end

  hosts.each do |num, name|
    console = <<~HEREDOC
    console #{name} {
      exec /usr/local/bin/ipmi-sol #{servers[num]};
    }
    HEREDOC
    File.open('conserver.cf', 'a') { |f| f << console }
  end

end

host_file = "/etc/mac2host"
server_file = "/etc/servers.info"

if File.exist?(host_file) and File.exist?(server_file)
  generate_conserver_by_cfg(host_file, server_file)
else
  generate_conserver_by_lab(lab)
end
