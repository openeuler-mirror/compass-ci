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

    You can login the jumper server cross the following url:

      https://jumper.compass-ci.openeuler.org/?hostname=#{account_info['jumper_host']}&username=#{account_info['my_login_name']}&port=#{account_info['jumper_port']}

    Notice:

      The account-vm server is only allowed to login with secret key, please save your private key.
      Case your private key for the public key you offered has changed and lead to login failures, you can contact our technical support staff for help:

        name:       Luan Shengde
        phone:      15109218229
        email:      luanshengde@compass-ci.org

    regards
    compass-ci
  EMAIL_MESSAGE

  return message
end
