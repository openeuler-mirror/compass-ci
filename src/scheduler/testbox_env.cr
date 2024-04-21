# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Job < JobHash
  def get_service_env
    yaml_any = YAML.parse File.read("/etc/compass-ci/service/service-env.yaml")
    yaml_any.as_h.delete("SCHED_NODES")

    hash = Hash(String, YAML::Any).new
    hash["services"] = yaml_any
    JobHash.new((JSON.parse(hash.to_json).as_h))
  end

  def get_testbox_env(flag = "local")
    yaml_any = YAML.parse File.open("/etc/compass-ci/scheduler/#{flag}-testbox-env.yaml")

    hash = Hash(String, YAML::Any).new
    hash["services"] = yaml_any
    JobHash.new((JSON.parse(hash.to_json).as_h))
  end
end
