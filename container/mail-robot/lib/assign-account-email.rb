#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

def build_apply_account_email(my_info, account_info, assign_account_vm)
  email_greeting = if my_info['bisect']
                     'We have automatically created the following information for you.'
                   else
                     'Thank you for joining us.'
                   end

  login_msg = <<~LOGIN_MSG

    You can login the jumper server cross the following url:

      https://jumper.compass-ci.openeuler.org/?hostname=#{account_info['jumper_host']}&username=#{account_info['my_login_name']}&port=#{account_info['jumper_port']}

    Notice:

      The account-vm server is only allowed to login with secret key, please save your private key.
      Case your private key for the public key you offered has changed and lead to login failures, you can contact our technical support staff for help:

        name:       Luan Shengde
        phone:      15109218229
        email:      luanshengde@compass-ci.org

  LOGIN_MSG

  login_account_vm = assign_account_vm ? login_msg : ''

  email_msg = <<~EMAIL_MESSAGE
    To: #{my_info['my_email']}
    Subject: [compass-ci] Account Ready

    Dear #{my_info['my_name']},

    #{email_greeting}
    #{login_account_vm}
    You need to do the following configurations before submitting a job:

    notice:
      (1-2) are ONE-TIME setup

    1) setup default config
       run the following command to add the below setup to default config file

         mkdir -p ~/.config/compass-ci/defaults/
         cat >> ~/.config/compass-ci/defaults/account.yaml <<-EOF
             my_email: #{my_info['my_email']}
             my_name: #{my_info['my_name']}
             my_account: #{my_info['my_account']}
             lab: #{ENV['lab']}
         EOF
         mkdir -p ~/.config/compass-ci/include/lab
         cat   >> ~/.config/compass-ci/include/lab/#{ENV['lab']}.yaml <<-EOF
             my_token: #{my_info['my_token']}
         EOF

    2) download lkp-tests and dependencies
       run the following command to install and setup lkp-test

         git clone https://gitee.com/compass-ci/lkp-tests.git
         cd lkp-tests
         make install
         source ~/.\${SHELL##*/}rc

    3) submit job
       reference: https://gitee.com/openeuler/compass-ci/blob/master/doc/help/tutorial.md

       reference to 'how to write job yaml' section to write the job yaml
       you can also reference to files in lkp-tests/jobs as example.

       submit jobs, for example:

         submit -m iperf.yaml testbox=vm-2p8g

    regards
    compass-ci
  EMAIL_MESSAGE

  return email_msg
end
