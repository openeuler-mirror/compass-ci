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

  property redis_host : String = JOB_REDIS_HOST
  property redis_port : Int32 = JOB_REDIS_PORT
  property redis_passwd : String = ""
  property redis_is_cluster : Bool = false

  STRING_OPTIONS = %w(
      lab_id
      redis_host
      redis_passwd
  )
  NUMBER_OPTIONS = %w(
      sched_port
      redis_port
  )
  BOOL_OPTIONS = %w(
      redis_is_cluster
  )

  def initialize
  end

  # call in the end, after SchedOptions.from_yaml()
  def load_env

  {% for name in STRING_OPTIONS %}
    {{name.id}} = ENV[{{name.stringify}}] if ENV.has_key?({{name.stringify}})
  {% end %}

  {% for name in NUMBER_OPTIONS %}
    {{name.id}} = ENV[{{name.stringify}}].to_i32 if ENV.has_key?({{name.stringify}})
  {% end %}

  {% for name in BOOL_OPTIONS %}
    {{name.id}} = to_bool({{name.stringify}}) if ENV.has_key?({{name.stringify}})
  {% end %}

  end

end

def to_bool(str : String) : Bool
  case str.downcase
  when "true", "yes", "1"
    true
  when "false", "no", "0"
    false
  else
    raise ArgumentError.new("Cannot convert '#{str}' to a boolean")
  end
end

