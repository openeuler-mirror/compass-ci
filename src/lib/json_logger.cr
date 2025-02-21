# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "log"
require "json"
require "kemal"

add_context_storage_type(Time::Span)

alias LogHash = Hash(String, String)
alias LogData = Hash(String, String) | Exception | String

class JSONLogger < Log
  def initialize
    @info_hash = Hash(String, String).new
    super("", Log::IOBackend.new(formatter: my_formatter), Log::Severity.from_value(Sched.options.log_level))
  end

  # Improved logging methods with exception and hash handling
  def trace(msg : LogData)
    log(:trace, msg)
  end

  def debug(msg : LogData)
    log(:debug, msg)
  end

  def info(msg : LogData)
    log(:info, msg)
  end

  def notice(msg : LogData)
    log(:notice, msg)
  end

  def warn(msg : LogData)
    log(:warn, msg)
  end

  def error(msg : LogData)
    log(:error, msg)
  end

  def fatal(msg : LogData)
    log(:fatal, msg)
  end

  # Generic log method to handle all severity levels
  private def log(severity : Symbol, msg : LogData)
    case severity
    when :trace
      self.trace { process_message(msg) }
    when :debug
      self.debug { process_message(msg) }
    when :info
      self.info { process_message(msg) }
    when :notice
      self.notice { process_message(msg) }
    when :warn
      self.warn { process_message(msg) }
    when :error
      self.error { process_message(msg) }
    when :fatal
      self.fatal { process_message(msg) }
    else
      raise ArgumentError.new("Unknown severity level: #{severity}")
    end
  end

  # Process the message and store exception/hash information
  private def process_message(msg : LogData)
    case msg
    when Exception
      msg.inspect_with_backtrace
    when LogHash
      @info_hash = msg.as(LogHash)
      ""
    when String
      msg.as(String)
    end
  end

  def my_formatter
    Log::Formatter.new do |entry, io|
      # next unless entry.severity.to_i32 >= Sched.options.log_level

      # Use local timezone or UTC for the timestamp
      datetime = entry.timestamp.to_s("%Y-%m-%d %H:%M:%S%z")
      level = entry.severity.to_s.upcase

      # Integrate message of types Exception | Hash(String, String)
      message = LogHash.new
      unless entry.message.empty?
        message.merge!({"message" => entry.message})
      end

      logger_hash = message.merge @info_hash
      @info_hash.clear

      # Send job event if job_id is present
      if logger_hash.has_key?("job_id")
        jobid = logger_hash["job_id"].to_i64
        Sched.instance.send_job_event(jobid, logger_hash.to_json)
      end

      # Build the TSV+KV line
      tsv_line = [datetime, level, logger_hash.delete("message")].join("\t")
      kv_pairs = logger_hash.map { |key, value| "#{key}=#{value}" }.join("\t")

      # Write the TSV+KV line to the output
      io << tsv_line << "\t" << kv_pairs
    end
  end

  def set_env(env : HTTP::Server::Context)
    @env = env
  end
end
