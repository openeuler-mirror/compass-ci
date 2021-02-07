#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'mail'
require 'rest-client'

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

    @my_info = {
      'my_email' => mail_content.from[0],
      'my_name' => mail_content.From.unparsed_value.gsub(/ <[^<>]*>/, '').gsub(/"/, ''),
      'my_ssh_pubkey' => []
    }
  end

  def build_my_info
    @my_info['my_commit_url'] = parse_commit_url
    @my_info['my_ssh_pubkey'] << parse_pub_key

    return @my_info
  end

  def extract_mail_content_body
    mail_content_body = @mail_content.part[0].part[0].body.decoded || \
                        @mail_content.part[0].body.decoded || \
                        @mail_content.body.decoded

    return mail_content_body
  end

  def extract_users
    users = extract_mail_content_body.split(/\r|\n/)
    users.delete('')
    users
  end

  def extract_commit_url
    mail_content_line = extract_mail_content_body.gsub(/\n/, '')
    # the commit url should be headed with a prefix: my oss commit
    # the commit url should be in a standart format, example:
    # my oss commit: https://github.com/torvalds/aalinux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03
    unless mail_content_line.match?(%r{my oss commit:\s*https?://[^/]*/[^/]*/[^/]*/commit/[\w\d]{40}})
      raise 'URL_PREFIX_ERR' unless mail_content_line.match?(%r{my oss commit:\s*https?://})
      raise 'NO_COMMIT_URL' unless mail_content_line.match?(%r{https?://[^/]*/[^/]*/[^/]*/commit/[\w\d]{40}})
    end

    mail_content_line.match(%r{https?://[^/]*/[^/]*/[^/]*/commit/[\w\d]{40}})[0]
  end

  def parse_commit_url
    url = extract_commit_url
    base_url = url.gsub(%r{/commit/[\w\d]{40}$}, '')

    base_url_in_upstream_repos('/c/upstream-repos', base_url)
    commit_url_availability(url, base_url)

    return url
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

    %x(/usr/bin/git -C /tmp clone --bare  #{repo_url} #{repo_dir})

    # get all commit IDs and check commit id exists
    repo_commits = %x(/usr/bin/git -C /tmp/#{repo_dir} log --pretty=format:'%H').split(/\n/)
    check_commit_exist(commit_id, repo_commits)

    # get the auther's email for the commit
    author_email = %x(/usr/bin/git -C /tmp/#{repo_dir} show -s --format=%aE #{commit_id}).chomp
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
