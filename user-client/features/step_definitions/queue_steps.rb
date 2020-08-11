# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require "#{File.dirname(__FILE__)}/../../src/lkp_server_info"
require "#{File.dirname(__FILE__)}/../../src/lkp_client"

Given(/^lkp server is ready$/) do
  @lkp_si = LkpServerInfo.new
  raise "Can not connect to server #{@lkp_si.host}" unless @lkp_si.connect_able
end

# task_description: {"add job status", "queue job result"}
Then(/^the lkp server echo (.*?)$/) do |task_description|
  puts @job_status
  raise "Server #{@lkp_si.host} not respond to #{task_description}" unless @job_status != ''
end

#     user: centos
#      cmd: {"lkp queue jobs/myjobs.yaml", "lkp result job/myjobs.yaml"}
# cmd_desc: {"add job", "queue job result"}
When(/^user "([^"]*)" use "([^"]*)" to (.*?)$/) do |_user, cmd, _cmd_desc|
  @lkp_client.cmd(cmd)
  respond = @lkp_client.run

  @job_status = ''
  raise "Post to server #{@lkp_si.host} error, code = #{respond.code}" unless respond.code != '200'

  @job_status = respond.body
end

And(/^user "([^"]*)" has logged in$/) do |_user|
  @lkp_client = LkpClient.new(@lkp_si)
  @lkp_client.basic_authorization
end
