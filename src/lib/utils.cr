# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./json_logger"

module Utils
  extend self

  def get_host_info(testbox)
    file_name = testbox =~ /^(vm-|dc-)/ ? testbox.split(".")[0] : testbox
    host_info_file = "#{CCI_REPOS}/#{LAB_REPO}/hosts/#{file_name}"

    host_info = Hash(String, JSON::Any).new
    return host_info unless File.exists?(host_info_file)

    host_info["#! #{host_info_file}"] = JSON::Any.new(nil)
    yaml_any = YAML.parse(File.read(host_info_file)).as_h
    host_info.merge!(Hash(String, JSON::Any).from_json(yaml_any.to_json))

    return host_info
  end

  def is_valid_account?(my_info, account_info)
    return false unless account_info.is_a?(JSON::Any)

    account_info = account_info.as_h

    return false unless my_info["my_name"]? == account_info["my_name"]?
    return false unless my_info["my_token"]? == account_info["my_token"]?
    return false unless my_info["my_account"]? == account_info["my_account"]?
    return true
  end

  def check_account_info(my_info, account_info)
    error_msg = "Failed to verify the account.\n"
    error_msg += "Please refer to https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/user-guide/apply-account.md"

    unless my_info["my_account"]?
      error_msg = "Missing required job key: my_account.\n"
      error_msg += "We generated the my_account for you automatically.\n"
      error_msg += "Add 'my_account: #{account_info["my_account"]}' to: "
      error_msg += "~/.config/compass-ci/defaults/account.yaml\n"
      error_msg += "You can also re-send 'apply account' email to specify a custom my_account name.\n"
      flag = false
    end

    flag = is_valid_account?(my_info, account_info) unless flag == false
    return if flag

    JSONLogger.new.warn({
      "msg" => "Invalid account",
      "my_email" => my_info["my_email"]?.to_s,
      "my_name" => my_info["my_name"]?.to_s,
      "suite" => my_info["suite"]?.to_s,
      "testbox" => my_info["testbox"]?.to_s
    }.to_json)

    raise error_msg
  end
end

