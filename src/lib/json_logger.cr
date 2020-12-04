# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "logger"
require "json"
require "any_merge"

class JSONLogger < Logger
  def initialize(logdev = STDOUT, formatter = my_formatter, @env = nil)
    @env_info = Hash(String, String | Int32).new
    super(logdev, formatter: formatter)
  end

  def my_formatter
    Logger::Formatter.new do | severity, datetime, progname, msg, io|
      get_env_info(@env.as(HTTP::Server::Context)) if @env
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
      logger_hash.any_merge!(@env_info)

      io << logger_hash.to_json
    end
  end

  private def get_env_info(env : HTTP::Server::Context)
    @env_info["status_code"] = env.response.status_code
    @env_info["method"] = env.request.method
    @env_info["resource"] = env.request.resource

    elapsed = get_elapsed(env)
    @env_info["elapsed"] = elapsed.to_s if elapsed
  end

  private def get_elapsed(env : HTTP::Server::Context)
    start_time = env.get?("start_time")
    return unless start_time

    elapsed = (Time.monotonic - start_time.as(Time::Span)).total_milliseconds
    return "#{elapsed.round(2)}ms" if elapsed >= 1

    "#{(elapsed * 1000).round(2)}µs"
  end

  def set_env(env : HTTP::Server::Context)
    @env = env
  end
end
