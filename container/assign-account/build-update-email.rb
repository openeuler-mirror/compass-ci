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

      You can login the jumper server cross the following url:

        https://jumper.compass-ci.openeuler.org/?hostname=#{account_info['jumper_host']}&username=#{account_info['my_login_name']}&port=#{account_info['jumper_port']}

      Notice:

        You can directly use the public key you offered to login the jumper server.

        Case your private key for the public key you offered has changed and lead to login failures, you can contact our technical support staff for help:

        name:       Luan Shengde
        phone:      15109218229
        email:      luanshengde@compass-ci.org

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
