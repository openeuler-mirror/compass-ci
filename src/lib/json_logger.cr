# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "logger"
require "json"
require "any_merge"

class JSONLogger < Logger
  FORMATTER = Logger::Formatter.new do | severity, datetime, progname, msg, io|
    level_num = severity.to_i32
    logger_hash = JSON.parse(%({"level_num": #{level_num},
                                "level": "#{severity}",
                                "time": "#{datetime}"
                                })).as_h

    logger_hash.any_merge!({"progname" => progname}) unless progname.empty?
    logger_hash.merge!(JSON.parse(%({"caller": #{caller}})).as_h) if level_num >= 2

    begin
      message = JSON.parse(msg).as_h
    rescue
      message = {"message" => msg}
    end
    logger_hash.any_merge!(message)

    io << logger_hash.to_json
  end

  def initialize(logdev = STDOUT, formatter = FORMATTER)
    super(logdev, formatter: formatter)
  end
end
