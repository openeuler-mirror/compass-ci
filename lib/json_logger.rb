# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'logger'
require 'json'

# print logs in JSON format
class JSONLogger < Logger
  LEVEL_INFO = {
    'TRACE' => 0,
    'DEBUG' => 1,
    'INFO' => 2,
    'NOTICE' => 3,
    'WARN' => 4,
    'ERROR' => 5,
    'FATAL' => 6
  }.freeze

  FORMATTER = proc { |severity, _datetime, progname, msg|
    level_num = LEVEL_INFO[severity]
    logger_hash = {
      'level' => severity.to_s,
      'level_num' => level_num,
      'time' => Time.now.strftime('%Y-%m-%dT%H:%M:%S.%3N+0800')
    }

    logger_hash['progname'] = progname if progname

    msg = { 'message' => msg } unless msg.is_a?(Hash)
    logger_hash.merge!(msg)

    logger_hash.to_json + "\n"
  }

  def initialize(logdev = STDOUT, formatter = FORMATTER)
    super(logdev, formatter: formatter)
  end
end

def log_info(msg)
  log = JSONLogger.new
  log.info(msg)
end

def log_warn(msg)
  log = JSONLogger.new
  log.warn(msg)
end

def log_error(msg)
  log = JSONLogger.new
  log.error(msg)
end
