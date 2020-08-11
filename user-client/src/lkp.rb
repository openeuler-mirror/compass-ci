# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require "#{File.dirname(__FILE__)}/lkp_client"
require "#{File.dirname(__FILE__)}/lkp_server_info"

if ARGV.size != 2
  puts 'cmd like: lkp queue myjobs.yaml'
else
  server = LkpServerInfo.new
  client = LkpClient.new(server)

  client.basic_authorization
  client.cmd("lkp #{ARGV[0]} #{ARGV[1]}")
  respon = client.run

  puts "add job as jobid = #{respon}"
end
