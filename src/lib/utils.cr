# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "yaml"
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

  def get_project_info(json_file, project_name)
    begin
      jf = File.read(json_file)
      data = JSON.parse(jf)
      return data.as_h[project_name]
    rescue JSON::ParseException | KeyError | File::NotFoundError
      return nil
    end
  end

  def get_service_env
    hash = Hash(String, JSON::Any).new
    yaml_any = File.open("/etc/compass-ci/service/service-env.yaml") do |content|
      YAML.parse(content).as_h?
    end
    return hash unless yaml_any

    return Hash(String, JSON::Any).from_json(yaml_any.to_json)
  end

  def remote_testbox_env
    hash = Hash(String, JSON::Any).new
    begin
      yaml_any = File.open("/etc/compass-ci/service/remote-testbox-env.yaml") do |content|
        YAML.parse(content).as_h?
      end
      hash.merge!(Hash(String, JSON::Any).from_json(yaml_any.to_json)) if yaml_any
      return hash
    rescue File::NotFoundError
      return hash
    end
  end

  def testbox_env(flag = "local", emsx = "ems1")
    master_hash = get_k8s_service_env("ems1")
    k8s_hash = get_k8s_service_env(emsx)
    master_hash.merge!(k8s_hash)

    yaml_any = get_out_service_keys
    hash = Hash(String, JSON::Any).new
    hash.merge!(Hash(String, JSON::Any).from_json(yaml_any.to_json))

    hash.each do |key, value|
      if master_hash.has_key?(key)
        hash[key] = master_hash[key]
      end
    end

    hash
  end

  def get_out_service_keys
    yaml_any = File.open("/etc/compass-ci/scheduler/local-testbox-env.yaml") do |content|
      YAML.parse(content).as_h?
    end

    return yaml_any
  end

  def get_k8s_service_env(emsx)
    hash = Hash(String, JSON::Any).new
    yaml_any = File.open("/etc/compass-ci/service/k8s-env.yaml") do |content|
      YAML.parse(content).as_h?
    end
    return hash unless yaml_any

    hash.merge!(Hash(String, JSON::Any).from_json(yaml_any.to_json))
    emsx_info = hash[emsx]?
    if emsx_info
      return emsx_info.as_h
    end

    return Hash(String, JSON::Any).new
  end

  def parse_emsx(os_project)
    return "ems1" if os_project.nil?

    project_info = get_project_info("#{ENV["CCI_SRC"]}/src/lib/openeuler-projects.json", os_project)
    return "ems1" if project_info.nil?

    return "#{project_info["processed_by_server"]}"
  end

  def parse_vms
    begin
      Hash(String, Hash(String, Hash(String, String))).from_yaml(File.read("/etc/compass-ci/scheduler/vms.yaml"))
    rescue File::NotFoundError
      pp "cant find /etc/compass-ci/scheduler/vms.yaml"
      return Hash(String, Hash(String, Hash(String, String))).new
    end
  end
end
