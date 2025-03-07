# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2025 Huawei Technologies Co., Ltd. All rights reserved.

require "yaml" # For parsing the config file
require "./constants"

# Configuration options, the first found file takes effect
SCHEDULER_CONFIG_FILES = [
  "#{ENV["HOME"]}/.config/compass-ci/scheduler/config.yaml",
  "/etc/compass-ci/scheduler/config.yaml",
]

struct SchedOptions
  include YAML::Serializable

  property log_level : Int32 = 0
  property admin_token : String = ""

  property skip_account_verification : Bool = true

  property should_read_es : Bool = false
  property should_write_es : Bool = false
  property should_read_manticore : Bool = false
  property should_write_manticore : Bool = false

  # N is a 1-3 digit integer representing the worker ID in a data-sharing cluster.
  # All workers in one cluster must have same cluster_size and unique worker_id
  # to ensure data ID merged into the same database maintains chronological order
  # and won't conflict.
  property worker_id : Int32 = 0
  property cluster_size : Int32 = 100 # Must be one of 10, 100, or 1000
  property worker_id_padded : String = "00" # Cached padded worker_id

  property sched_port : Int32 = 3000

  property es_host : String = JOB_ES_HOST
  property es_port : Int32 = JOB_ES_PORT
  property es_user : String = ""
  property es_password : String = ""

  property manticore_host : String = JOB_MANTICORE_HOST
  property manticore_port : Int32 = JOB_MANTICORE_PORT

  property ipmi_user : String = ""
  property ipmi_password : String = ""

  STRING_OPTIONS = %w(
      worker_id
      es_host
      es_user
      es_password
      manticore_host
  )
  NUMBER_OPTIONS = %w(
      sched_port
      es_port
      manticore_port
  )
  BOOL_OPTIONS = %w(
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

  def validate
    validate_worker_id
    @worker_id_padded = pad_worker_id(@worker_id, @cluster_size)
  end

  private def validate_worker_id
    case @cluster_size
    when 10
      raise ArgumentError.new("worker_id must be between 0 and 9 for cluster_size=10") unless (0..9).includes?(@worker_id)
    when 100
      raise ArgumentError.new("worker_id must be between 0 and 99 for cluster_size=100") unless (0..99).includes?(@worker_id)
    when 1000
      raise ArgumentError.new("worker_id must be between 0 and 999 for cluster_size=1000") unless (0..999).includes?(@worker_id)
    else
      raise ArgumentError.new("cluster_size must be one of 10, 100, or 1000")
    end
  end

  private def pad_worker_id(worker_id : Int32, cluster_size : Int32) : String
    case cluster_size
    when 10
      "%01d" % worker_id
    when 100
      "%02d" % worker_id
    when 1000
      "%03d" % worker_id
    else
      raise "Invalid cluster_size"
    end
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

