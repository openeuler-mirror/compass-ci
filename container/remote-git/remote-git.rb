#!/usr/bin/ruby
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
    return JSON.dump({ 'status': 100, 'errmsg': 'parse json error' })
  end
  # check if the parameters are complete
  params_complete_result = check_params_complete(data)
  return params_complete_result if params_complete_result

  # check whether the git_command parameter meets the requirements
  git_command_check_result = check_git_params(data['git_command'])
  return git_command_check_result if git_command_check_result

  # check if git_command contains illegal characters
  check_illegal_char_result = check_illegal_char(data['git_command'])
  return check_illegal_char_result if check_illegal_char_result

  # check if git repository exists
  repo_path = File.join(GIT, data['project'], data['developer_repo'])
  return JSON.dump({ 'status': 200, 'errmsg': 'repository not exists' }) unless File.exist?(repo_path)

  # execute git command
  Dir.chdir(repo_path)
  _stdin, stdout, stderr, wait_thr = Open3.popen3(*data['git_command'])
  out = stdout.read.force_encoding('ISO-8859-1').encode('UTF-8')
  err = stderr.read
  exit_code = wait_thr.value.to_i

  { 'status': 0, 'stdout': out, 'stderr': err, 'exit_code': exit_code }.to_json
end

def check_git_params(git_command)
  return JSON.dump({ 'status': 104, 'errmsg': 'git_command params type error' }) if git_command.class != Array
  return JSON.dump({ 'status': 105, 'errmsg': 'git_command length error' }) if git_command.length < 2

  JSON.dump({ 'status': 107, 'errmsg': 'not git-* command' }) unless git_command[0].start_with? 'git-'
  git_command[0] = "/usr/lib/git-core/#{git_command[0]}"
  return nil
end

def check_params_complete(params)
  return JSON.dump({ 'status': 101, 'errmsg': 'no project params' }) unless params.key?('project')
  return JSON.dump({ 'status': 102, 'errmsg': 'no developer_repo params' }) unless params.key?('developer_repo')
  return JSON.dump({ 'status': 103, 'errmsg': 'no git_command params' }) unless params.key?('git_command')
end

def check_illegal_char(git_command)
  return unless git_command.length > 1

  detected_string = git_command.join
  ILLEGAL_SHELL_CHAR.each do |char|
    return JSON.dump({ 'status': 108, 'errmsg': 'git_command params illegal' }) if detected_string.include?(char)
  end
end
