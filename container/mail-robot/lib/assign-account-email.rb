#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

def build_apply_account_email(my_info)
  email_msg = <<~EMAIL_MESSAGE
    To: #{my_info['my_email']}
    Subject: [compass-ci] Account Ready

    Dear #{my_info['my_name']},

    Thank you for joining us.

    You can use the following info to submit jobs:

    notice:
      (1-2) are ONE-TIME setup

    1) setup default config
       run the following command to add the below setup to default config file

         mkdir -p ~/.config/compass-ci/defaults/
         cat >> ~/.config/compass-ci/defaults/account.yaml <<-EOF
             my_email: #{my_info['my_email']}
             my_name: #{my_info['my_name']}
             lab: #{ENV['lab']}
         EOF
         mkdir -p ~/.config/compass-ci/include/lab
         cat   >> ~/.config/compass-ci/include/lab/#{ENV['lab']}.yaml <<-EOF
             my_token: #{my_info['my_token']}
         EOF

    2) download lkp-tests and dependencies
       run the following command to install and setup lkp-test

         git clone https://gitee.com/wu_fengguang/lkp-tests.git
         cd lkp-tests
         make install
         source ${HOME}/.${SHELL##*/}rc

    3) submit job
       reference: https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/tutorial.md

       reference to 'how to write job yaml' section to write the job yaml
       you can also reference to files in lkp-tests/jobs as example.

       submit jobs, for example:

         submit -m iperf.yaml testbox=vm-2p8g

    regards
    compass-ci
  EMAIL_MESSAGE

  return email_msg
end
