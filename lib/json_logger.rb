# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'logger'
require 'json'

# print logs in JSON format
class JSONLogger < Logger
  LEVEL_INFO = {
    'DEBUG' => 0,
    'INFO' => 1,
    'WARN' => 2,
    'ERROR' => 3,
    'FATAL' => 4,
    'UNKNOWN' => 5
  }.freeze

  FORMATTER = proc { |severity, datetime, progname, msg|
    level_num = LEVEL_INFO[severity]
    logger_hash = {
      'level' => severity.to_s,
      'level_num' => level_num,
      'time' => datetime
    }

    logger_hash['progname'] = progname if progname
    logger_hash['caller'] = caller if level_num >= 2

    msg = { 'message' => msg } unless msg.is_a?(Hash)
    logger_hash.merge!(msg)

    logger_hash.to_json
  }

  def initialize(logdev = STDOUT, formatter = FORMATTER)
    super(logdev, formatter: formatter)
  end
end
