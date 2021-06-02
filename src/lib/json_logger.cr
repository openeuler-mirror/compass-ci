# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "logger"
require "json"
require "any_merge"
require "kemal"

add_context_storage_type(Time::Span)

class JSONLogger < Logger
  def initialize(logdev = STDOUT, formatter = my_formatter, @env = nil)
    @env_info = Hash(String, String | Int32 | Float64 | JSON::Any).new
    super(logdev, formatter: formatter)
  end

  def my_formatter
    Logger::Formatter.new do | severity, datetime, progname, msg, io|
      get_env_info(@env.as(HTTP::Server::Context)) if @env
      level_num = severity.to_i32
      datetime = datetime.to_s("%Y-%m-%dT%H:%M:%S.%3N+0800")
      logger_hash = JSON.parse(%({"level_num": #{level_num},
                                  "level": "#{severity}",
                                  "time": "#{datetime}"
                                  })).as_h

      logger_hash.any_merge!({"progname" => progname}) unless progname.empty?

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

    @env_info["testbox"] = env.get?("testbox").to_s if env.get?("testbox")
    @env_info["job_id"] = env.get?("job_id").to_s if env.get?("job_id")
    @env_info["job_state"] = env.get?("job_state").to_s if env.get?("job_state")

    set_elapsed(env)
    merge_env_log(env)
  end

  private def merge_env_log(env)
    return unless log = env.get?("log")

    log = JSON.parse(log.to_s).as_h
    @env_info.any_merge!(log)
  end

  private def set_elapsed(env : HTTP::Server::Context)
    start_time = env.get?("start_time")
    return unless start_time

    elapsed_time = (Time.monotonic - start_time.as(Time::Span)).total_milliseconds
    @env_info["elapsed_time"] = elapsed_time

    if elapsed_time >= 1
      elapsed = "#{elapsed_time.round(2)}ms"
    else
      elapsed = "#{(elapsed_time * 1000).round(2)}µs"
    end

    @env_info["elapsed"] = elapsed
  end

  def set_env(env : HTTP::Server::Context)
    @env = env
  end
end
