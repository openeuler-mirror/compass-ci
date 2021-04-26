#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

def email_err_message(message)
  err_message = ''
  case message
  when 'NO_COMMIT_URL'
    err_message = <<~EMAIL_MESSAGE
      No commit url found.
      You should add a commit url for the 'apply account' email.

      For example:
        my_oss_commit: https://github.com/torvalds/linux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03
    EMAIL_MESSAGE
  when 'URL_PREFIX_ERR'
    err_message = <<~EMAIL_MESSAGE
      Please add a correct prefix for the commit url.

          my_oss_commit

      For example:

          my_oss_commit: https://github.com/torvalds/linux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03
    EMAIL_MESSAGE
  when 'NOT_REGISTERED'
    err_message = <<~EMAIL_MESSAGE
      Your repo has not been registered to our upstream-repos yet.
      You should register your repo to the upstream first.
      Try again after you have done it.

      Reference the following url to learn how to register the repo:

          https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/test-oss-project.en.md
    EMAIL_MESSAGE
  when 'COMMIT_AUTHOR_ERROR'
    err_message = <<~EMAIL_MESSAGE
      We cannot confirm the commit author matches your email.
      Make sure it is truely submitted with your email.

      Choose a commit that was submitted with your own email and try again.
    EMAIL_MESSAGE
  when 'NO_COMMIT_ID'
    err_message = <<~EMAIL_MESSAGE
      There is no such commit ID in the repo.

      Please check the commit ID exists.
      or
      You have write the commit ID correctly.
    EMAIL_MESSAGE
  when 'NO_PUBKEY'
    err_message = <<~EMAIL_MESSAGE
      No pub_key found.
      Please add a pubkey to the email and then try again.
    EMAIL_MESSAGE
  when 'PUBKEY_NAME_ERR'
    err_message = <<~EMAIL_MESSAGE
      Pubkey file name error, keep its name as when it was generated.
      The pubkey file name should like:

          id_{{ xxx }}.pub
    EMAIL_MESSAGE
  end

  err_message += <<~EMAIL_MESSAGE

    Manual for how to apply account:

        https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/apply-account.md
  EMAIL_MESSAGE

  err_message
end

def build_apply_account_fail_email(my_info, message)
  err_message = email_err_message(message)
  email_msg = <<~EMAIL_MESSAGE
    To: #{my_info['my_email']}
    Subject: [compass-ci] apply account failed

    Dear user:

    Your application for account failed.

    #{err_message}

    regards
    compass-ci
  EMAIL_MESSAGE

  return email_msg
end
