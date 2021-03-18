# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Job
  def get_service_env
    hash = Hash(String, JSON::Any).new
    yaml_any = File.open("/etc/compass-ci/service/service-env.yaml") do |content|
      YAML.parse(content).as_h?
    end
    return hash unless yaml_any

    return Hash(String, JSON::Any).from_json(yaml_any.to_json)
  end

  def testbox_env(flag = "local")
    service_env = get_service_env
    hash = Hash(String, JSON::Any).new

    yaml_any = File.open("/etc/compass-ci/scheduler/#{flag}-testbox-env.yaml") do |content|
      YAML.parse(content).as_h?
    end
    return hash unless yaml_any

    hash.merge!(Hash(String, JSON::Any).from_json(yaml_any.to_json))
    hash.each do |key, value|
      if value == nil
        hash[key] = service_env[key]
      end
    end

    hash
  end
end
