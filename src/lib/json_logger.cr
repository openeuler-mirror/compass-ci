# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "log"
require "json"
require "kemal"

add_context_storage_type(Time::Span)

class JSONLogger < Log
  def initialize(@env = nil)
    @env_info = Hash(String, String | Int32 | Int64).new
    super("", Log::IOBackend.new(formatter: my_formatter), :trace)
  end

  def trace(msg : Exception | String | Hash(String, String))
    self.trace { msg }
  end

  def debug(msg : Exception | String | Hash(String, String))
    self.debug { msg }
  end

  def info(msg : Exception | String | Hash(String, String))
    self.info { msg }
  end

  def notice(msg : Exception | String | Hash(String, String))
    self.notice { msg }
  end

  def warn(msg : Exception | String | Hash(String, String))
    self.warn { msg }
  end

  def error(msg : Exception | String | Hash(String, String))
    self.error { msg }
  end

  def fatal(msg : Exception | String | Hash(String, String))
    self.fatal { msg }
  end

  def my_formatter
    Log::Formatter.new do |entry, io|
      get_env_info(@env.as(HTTP::Server::Context)) if @env

      # Use local timezone or UTC for the timestamp
      datetime = entry.timestamp.to_s("%Y-%m-%d %H:%M:%S.%3N%z")
      level = entry.severity.to_s.upcase

      # Handle message of types Exception | String | Hash(String, String)
      msg = entry.message
      message = case msg
                when Exception
                  {"message" => msg.message.to_s, "exception" => msg.class.to_s}
                when String
                  {"message" => msg}
                when Hash
                  msg
                else
                  {"message" => msg.to_s}
                end

      # Merge message and @env_info
      logger_hash = message.merge(@env_info)

      # Send job event if job_id is present
      if logger_hash.has_key?("job_id")
        jobid = logger_hash["job_id"].to_i64
        Sched.instance.send_job_event(jobid, logger_hash.to_json)
      end

      # Build the TSV+KV line
      tsv_line = [level, datetime, logger_hash.delete("message")].join("\t")
      kv_pairs = logger_hash.map { |key, value| "#{key}=#{value}" }.join("\t")

      # Write the TSV+KV line to the output
      io << tsv_line << "\t" << kv_pairs
    end
  end

  private def get_env_info(env : HTTP::Server::Context)
    @env_info["status_code"] = env.response.status_code
    @env_info["method"] = env.request.method
    @env_info["resource"] = env.request.resource

    @env_info["testbox"] = env.get?("testbox").to_s if env.get?("testbox")
    @env_info["job_id"] = env.get?("job_id").to_s if env.get?("job_id")
    @env_info["job_state"] = env.get?("job_state").to_s if env.get?("job_state")
    @env_info["api"] = env.get?("api").to_s if env.get?("api")

    set_elapsed(env)
  end

  private def set_elapsed(env : HTTP::Server::Context)
    start_time = env.get?("start_time")
    return unless start_time

    elapsed_time = (Time.monotonic - start_time.as(Time::Span)).total_milliseconds
    @env_info["elapsed_time"] = elapsed_time.to_i32

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
