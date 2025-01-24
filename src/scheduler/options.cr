# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2025 Huawei Technologies Co., Ltd. All rights reserved.

require "yaml" # For parsing the config file
require "./constants"

# configuration options
SCHEDULER_CONFIG_FILE = "/etc/compass-ci/scheduler/config.yaml" # Default config file

struct SchedOptions
  include YAML::Serializable

  property has_redis : Bool = true
  property has_etcd : Bool = true
  property has_es : Bool = true
  property has_manticore : Bool = false

  property lab_id : String = "" # at most 3-digit int, or null
  property sched_port : Int32 = 3000

  def initialize
  end

  # call in the end, after SchedOptions.from_yaml()
  def load_env
    sched_port = ENV["sched_port"].to_i32 if ENV["sched_port"]?
    lab_id = ENV["lab_id"] if ENV["lab_id"]?
  end

end

