#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'mail'
require_relative 'gitee-commit-url-check'

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
#           execute curl to check the commit
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

  def extract_mail_content_line
    mail_content_body = @mail_content.part[0].part[0].body.decoded || \
                        @mail_content.part[0].body.decoded || \
                        @mail_content.body.decoded
    mail_content_line = mail_content_body.gsub(/\n/, '')

    return mail_content_line
  end

  def extract_commit_url
    mail_content_line = extract_mail_content_line
    # the commit url should be headed with a prefix: my oss commit
    # the commit url should be in a standart format, example:
    # my oss commit: https://github.com/torvalds/aalinux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03
    unless mail_content_line.match?(%r{my oss commit:\s*https?://[^/]*/[^/]*/[^/]*/commit/[\w\d]{40}})
      error_message = "No matched commit url found.\n"
      error_message += 'Ensure that you have add a right commit url, '
      error_message += "and with prefix 'my oss commit:'."
      raise error_message
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

    error_message = "The repo url for your commit is not in our upstream-repo list.\n"
    error_message += 'Use a new one, or consulting the manager for available repo list.'

    raise error_message
  end

  def commit_url_availability(url, base_url)
    hub_name = url.split('/')[2]

    # it requires authentication when execute curl to get the commit information
    # clone the repo and then validate the commit for the email address
    if hub_name.eql? 'gitee.com'
      gitee_commit(url, base_url)
    else
      non_gitee_commit(url)
    end
  end

  def gitee_commit(url, base_url)
    my_gitee_commit = GiteeCommitUrlCheck.new(@my_info, url, base_url)
    my_gitee_commit.gitee_commit_check
  end

  def non_gitee_commit(url)
    url_fdback = %x(curl #{url})
    email_index = url_fdback.index @my_info['my_email']

    return unless email_index.nil?

    error_message = "We can not confirm the commit url matches your email.\n"
    error_message += 'Make sure that the commit url is right,'
    error_message += ' or it is truely submitted with you email.'

    raise error_message
  end

  def parse_pub_key
    error_message = "No pub_key found.\n"
    error_message += 'Please add a pub_key as an attachment to your email.'

    raise error_message if @mail_content.attachments.empty?
    raise error_message unless @mail_content.attachments[0].filename =~ /^id_.*\.pub$/

    pub_key = @mail_content.attachments[0].body.decoded

    return pub_key
  end
end
