# SPDX-License-Identifier: MulanPSL-2.0+
# # Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# # frozen_string_literal: true
#
require_relative "#{ENV['CCI_SRC']}/lib/es_query"
require_relative "#{ENV['CCI_SRC']}/lib/assign_account_client"

def send_account_mail(user_info)
  account_info = ESQuery.new(index: 'accounts').query_by_id(user_info['my_email'])
  return {'status'=> true} if account_info

  begin
    apply_account = AutoAssignAccount.new(user_info)
    apply_account.send_account
  rescue
    return {'status' => false}
  end

  return {'status' => true}
end
