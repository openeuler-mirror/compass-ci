# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'logger'
require 'json'

# print logs in JSON format
class Log < Logger
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
    begin
      message = JSON.parse(msg)
    rescue JSON::ParserError
      message = { 'message' => msg }
    end
    h = {
      'level' => severity.to_s,
      'level_num' => level_num,
      'datetime' => datetime,
      'progname' => progname,
      'message' => ''
    }
    h.merge!(message)
    h.merge!({ 'caller' => caller }) if level_num >= 2
    h.to_json
  }

  def initialize(logdev = STDOUT, formatter = FORMATTER)
    super(logdev, formatter: formatter)
  end
end
