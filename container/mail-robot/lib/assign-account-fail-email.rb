#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

def email_err_message(message)
  err_message = ''
  case message
  when 'NO_PURPOSE'
    err_message = <<~EMAIL_MESSAGE
      You provides no purpose for your application.
      Please add your purpose for your application in the apply account email.
      example:
        my_purpose: learning compass-ci usage
    EMAIL_MESSAGE
  when 'NON_FORWARD_USER'
    err_message = <<~EMAIL_MESSAGE
      Only forward-issuers can forwarding the 'apply acccount' emails.
      If you want to forward the emails, please contact the administrator to ensure you are a forward-issuer.
    EMAIL_MESSAGE
  when 'NO_MY_ACCOUNT'
    err_message = <<~EMAIL_MESSAGE
      No my_account found.
      You should add a my_account in the 'apply account' email.
      This my_account will be your unique identity when you using the compass-ci.

      For example:
        my_account: rientjes
    EMAIL_MESSAGE
  when 'MY_ACCOUNT_EXIST'
    err_message = <<~EMAIL_MESSAGE
      The my_account you offered is already used.
      Please offer an new one and try again.

      For example:
        my_account: rientjes
    EMAIL_MESSAGE
  when 'NOT_REGISTERED'
    err_message = <<~EMAIL_MESSAGE
      Your repo has not been registered to our upstream-repos yet.
      You should register your repo to the upstream first.
      Try again after you have done it.

      Reference the following url to learn how to register the repo:

          https://gitee.com/openeuler/compass-ci/blob/master/doc/test-guide/test-oss-project.en.md
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

        https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/apply-account.md
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
