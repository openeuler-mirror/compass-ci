# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

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
end

