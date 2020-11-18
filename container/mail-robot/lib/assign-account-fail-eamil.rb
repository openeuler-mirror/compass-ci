#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

def build_apply_account_fail_email(my_info, message)
  email_msg = <<~EMAIL_MESSAGE
    To: #{my_info['my_email']}
    Subject: [compass-ci] apply account failed

    Dear user:

    Your application for account failed with following error:

      #{message}

    In order to successfully apply an account, please pay attention to the following points:

    1. mail subject
       The subject should exactly: apply account

    2. commit url
       When you writing the url, add prefix: my oss commit
       example:
         my oss commit: https://github.com/torvalds/aalinux/commit/7be74942f184fdfba34ddd19a0d995deb34d4a03

       attention:
         Ensure you commit url exist and available to access.

    3. ssh pubkey
       You need to add a pubkey as an attachment to the email.

    regards
    compass-ci
  EMAIL_MESSAGE

  return email_msg
end
