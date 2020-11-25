#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'mail'

# used to check commit available for hub gitee.com
# it is called when:
#   - ParseApplyAccountEmail execute commit_url_availability
#   - hub is gitee.com
#   gitee_commit_check
#     clone the repo
#     check commit available
class GiteeCommitUrlCheck
  def initialize(my_info, url, base_url)
    @my_info = my_info
    @url = url
    @base_url = base_url
  end

  def gitee_commit_check
    repo_url = [@base_url, 'git'].join('.')
    repo_dir = repo_url.split('/')[-1]
    commit_id = @url.split('/')[-1]

    Dir.chdir '/tmp'
    %x(/usr/bin/git clone --bare  #{repo_url} #{repo_dir})

    email_index = %x(/usr/bin/git -C #{repo_dir} show #{commit_id}).index @my_info['my_email']

    FileUtils.rm_rf repo_dir

    gitee_commit_exist(email_index)
  end

  def gitee_commit_exist(email_index)
    return if email_index

    error_message = "We can not confirm whether the commit url matches your email.\n"
    error_message += 'Make sure that the commit url is right,'
    error_message += ' or it is truely submitted with your email.'

    raise error_message
  end
end
