#!/usr/bin/ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'open3'

set :bind, '0.0.0.0'
set :port, 8100

GIT = '/srv/git'
ILLEGAL_SHELL_CHAR = %w[& $].freeze

post '/git_command' do
  request.body.rewind
  begin
    data = JSON.parse request.body.read
  rescue JSON::ParserError
    return [400, headers.update({ 'errcode' => '100', 'errmsg' => 'parse json error' }), '']
  end
  puts '-' * 50
  puts 'post body:', data

  begin
    # check if the parameters are complete
    check_params_complete(data)
    # check whether the git_command parameter meets the requirements
    check_git_params(data['git_command'])
    # check if git_command contains illegal characters
    check_illegal_char(data['git_command'])
    # check if git repository exists
    repo_path = File.join(GIT, data['git_repo'])
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'repository not exists' }) unless File.exist?(repo_path)
  rescue StandardError => e
    puts 'error message: ', e.message
    return [400, headers.update(JSON.parse(e.message)), '']
  end

  # execute git command
  _stdin, stdout, _stderr, wait_thr = Open3.popen3(*data['git_command'], :chdir=>repo_path)
  out = stdout.read
  exit_code = wait_thr.value.to_i

  [200, headers.update({ 'errcode' => '0', 'exit_code' => exit_code.to_s }), out]
end

def check_git_params(git_command)
  raise JSON.dump({ 'errcode' => '104', 'errmsg' => 'git_command params type error' }) if git_command.class != Array
  raise JSON.dump({ 'errcode' => '105', 'errmsg' => 'git_command length error' }) if git_command.length < 2
  raise JSON.dump({ 'errcode' => '107', 'errmsg' => 'not git-* command' }) unless git_command[0].start_with? 'git-'

  git_command[0] = "/usr/lib/git-core/#{git_command[0]}"
  return nil
end

def check_params_complete(params)
  raise JSON.dump({ 'errcode' => '101', 'errmsg' => 'no git_repo params' }) unless params.key?('git_repo')
  raise JSON.dump({ 'errcode' => '102', 'errmsg' => 'no git_command params' }) unless params.key?('git_command')
end

def check_illegal_char(git_command)
  detected_string = git_command.join
  ILLEGAL_SHELL_CHAR.each do |char|
    raise JSON.dump({ 'errcode' => '108', 'errmsg' => 'git_command params illegal' }) if detected_string.include?(char)
  end
  nil
end
