#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

def build_message(email, account_info)
  message = <<~EMAIL_MESSAGE
    To: #{email}
    Subject: [compass-ci] jumper account is ready

    Dear user:

    Thank you for joining us.
    You can use the following command to login the jumper server:

      Login command:
        ssh -p #{account_info['jumper_port']} #{account_info['my_login_name']}@#{account_info['jumper_host']}

      You can directly use the public key you offered to login the account-ver server.

      Case your private key for the public key you offered has changed and lead to login failures, you can contact our technical support staff for help:

        name:       Zhang Dewan
        phone:      18969058870
        email:      zhangdewan1@compass-ci.org

        name:       Luan Shengde
        phone:      15109218229
        email:      luanshengde@compass-ci.org

      Suggest:
        If you use the password to login, change it in time.

    regards
    compass-ci
  EMAIL_MESSAGE

  return message
end
