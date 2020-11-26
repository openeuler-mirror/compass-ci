#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

def build_update_message(email, account_info, conf_info)
  message = if conf_info['enable_login']

              <<~EMAIL_MESSAGE
      To: #{email}
      Subject: [compass-ci] account update notice

      Dear user:

      Your account has been update successfully.
      You can use the following command to login the server.

      Login command:
        ssh -p #{account_info['jumper_port']} #{account_info['my_login_name']}@#{account_info['jumper_host']}

      Account password:
        #{account_info['my_password']}

      regards
      compass-ci
              EMAIL_MESSAGE
            else
              <<~EMAIL_MESSAGE
      To: #{email}
      Subject: [compass-ci] account expiration notice

      Dear user:

        your account has expired.
        consult the manager for help if you want to continue using the account.

      regards
      compass-ci
              EMAIL_MESSAGE
            end

  return message
end
