#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

# set default system encoding
Encoding.default_external = Encoding::UTF_8

require 'json'
require 'mail'
require 'rest-client'
require 'git'
require_relative '../../../lib/build_account_info'

# used to parse mail_content for my_commit_url and my_ssh_pubkey
# be called by AssignAccount when it needs to extract required data:
#   - my_commit_url
#   - my_ssh_pubkey
#
# input: mail_content
# output: my_commit_url, my_ssh_pubkey
#
#   parse_commit_url
#     parse my_commit_url from the mail_content and return it
#     extract my_commit_url
#       extract my_coomit_url from the mail_content
#       check commit url exists
#     base_url_in_upstream_repos
#       check whether the base url in upstream-repos
#     commit_url_availability
#       check commit available
#         gitee.com:
#           call GiteeCommitUrlCheck to check the commit
#         non-gitee.com:
#           get request date for the commit url to check the commit
#   parse_pub_key
#     check my_ssh_pubkey exists and return it
class ParseApplyAccountEmail
  def initialize(mail_content)
    @mail_content = mail_content
    @mail_content_body = ''
    # forward_issuer is email info for user who do the email forward
    @forward_issuer =  File.exist?(ENV['FORWARD_ISSUER']) ? YAML.load_file(ENV['FORWARD_ISSUER']) : {}

    @my_info = {
      'my_email' => mail_content.from[0],
      'my_name' => mail_content.From.unparsed_value.gsub(/ *<[^<>]*>/, '').gsub(/"/, ''),
      'my_ssh_pubkey' => []
    }
  end

  def extract_mail_content_body
    @mail_content_body = @mail_content.part[0].part[0].body.decoded || \
                         @mail_content.part[0].body.decoded || \
                         @mail_content.body.decoded
  end

  def build_my_info
    email_subject = @mail_content.subject

    # if the email's sender is a forward_issuer, it will re-extract the
    # my_email, my_name, from the forwarded original email content.
    # case the email's sender is not a forward_issuer, it will throw error and
    # send fail email to the sender
    if email_subject =~ /fw: *apply account/i
      raise 'NON_FORWARD_USER' unless @forward_issuer.include? @my_info['my_email']

      extract_forwarded_email
    end

    extract_mail_content_body

    @my_info['my_commit_url'] = parse_commit_url unless parse_commit_url.nil?
    @my_info['my_account'] = parse_my_account
    @my_info['my_ssh_pubkey'] << parse_pub_key
    parse_apply_info

    return @my_info
  end

  def extract_forwarded_email
    forwarded_email = Mail.read_from_string(@mail_content_body)

    @my_info['my_email'] = forwarded_email.from[0]
    @my_info['my_name'] = forwarded_email.From.unparsed_value.gsub(/ *<[^<>]*>/, '').gsub(/"/, '')
  end

  def extract_users
    users_info = []

    users = @mail_content_body.split(/---+/)
    users.delete('')
    users.each do |user|
      user_info = YAML.safe_load(user)
      next if user_info.nil?
      next unless user_info.include?('my_email')

      users_info << user_info
    end

    return users_info
  end

  def extract_commit_url
    mail_content_line = @mail_content_body.gsub(/\n/, '')
    # the commit url should be headed with a prefix: my_oss_commit
    # the commit url should be in a standart format, example:
    # my_oss_commit: https://github.com/torvalds/aalinux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03
    # the prefix is renamed to 'my_oss_commit', but 'my oss commit' is still supportted.
    return unless mail_content_line.match?(%r{my[ _]oss[ _]commit:\s*https?://[^/]*/[^/]*/[^/]*/commit/[\w\d]{40}})

    mail_content_line.match(%r{https?://[^/]*/[^/]*/[^/]*/commit/[\w\d]{40}})[0]
  end

  def parse_commit_url
    url = extract_commit_url
    return nil if url.nil?

    base_url = url.gsub(%r{/commit/[\w\d]{40}$}, '')

    base_url_in_upstream_repos('/c/upstream-repos', base_url)
    commit_url_availability(url, base_url)

    return url
  end

  def parse_my_account
    my_account_line = extract_mail_content_body.match(/my_account:\s*[\w\-_]+/).to_s
    raise 'NO_MY_ACCOUNT' if  my_account_line.nil? ||  my_account_line.empty?

    my_account = YAML.safe_load(my_account_line)['my_account']
    @my_info['my_account'] = my_account

    check_my_account_uniq(@my_info['my_account'])

    return my_account
  end

  def check_my_account_uniq(_my_account)
    check_account = BuildMyInfo.new(@my_info['my_email'])

    return if check_account_unique(@my_info, check_account)

    raise 'MY_ACCOUNT_EXIST'
  end

  def parse_apply_info
    mail_content_lines = @mail_content_body.split("\n")
    mail_content_lines.each do |line|
      case line
      when /my_name:\s*(.*)/
        @my_info['my_name'] = $1.chomp
      when /my_gitee_account:\s*(.*)/
        @my_info['my_gitee_account'] = $1.chomp
      when /my_purpose:\s*(.*)/
        @my_info['my_purpose'] = $1.chomp
      when /my_company:\s*(.*)/
        @my_info['my_company'] = $1.chomp
      when /my_college:\s*(.*)/
        @my_info['my_college'] = $1.chomp
      end
    end

    raise 'NO_PURPOSE' unless @my_info.key?('my_purpose')
  end

  def base_url_in_upstream_repos(upstream_dir, base_url)
    Dir.chdir(upstream_dir)
    match_out = %x(grep -rn #{base_url})

    return unless match_out.empty?

    raise 'NOT_REGISTERED'
  end

  def commit_url_availability(url, base_url)
    repo_url = [base_url, 'git'].join('.')
    repo_dir = repo_url.split('/')[-1]
    commit_id = url.split('/')[-1]

    Git.clone(repo_url, repo_dir, path: '/tmp/', bare: true)

    # get all commit IDs and check commit id exists
    repo = Git.bare("/tmp/#{repo_dir}")
    repo_commits = repo.lib.log_commits
    check_commit_exist(commit_id, repo_commits)

    # get the auther's email for the commit
    author_email = repo.gcommit(commit_id).author.email
    check_commit_email(author_email)

    FileUtils.rm_rf "/tmp/#{repo_dir}"
  end

  def check_commit_exist(commit_id, repo_commits)
    return if repo_commits.include? commit_id.chomp

    raise 'NO_COMMIT_ID'
  end

  def check_commit_email(author_email)
    return if author_email.eql? @my_info['my_email'].chomp

    raise 'COMMIT_AUTHOR_ERROR'
  end

  def parse_pub_key
    raise 'NO_PUBKEY' if @mail_content.attachments.empty?
    raise 'PUBKEY_NAME_ERR' unless @mail_content.attachments[0].filename =~ /^id_.*\.pub$/

    pub_key = @mail_content.attachments[0].body.decoded

    return pub_key
  end
end
