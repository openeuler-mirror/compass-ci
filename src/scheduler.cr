# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./scheduler/constants.cr"
require "./scheduler/api.cr"
require "./lib/json_logger"
require "./lib/do_local_pack"
require "./lib/create_secrets_yaml"

require "kemal"
require "option_parser"

module Scheduler

  # Initialize the logger
  LOG = JSONLogger.new

  # Parse command-line options
  def self.parse_options
    config_file = SCHEDULER_CONFIG_FILE
    OptionParser.parse do |parser|
      parser.banner = "Usage: scheduler [arguments]"

      parser.on "-c CONFIG", "--config=CONFIG", "Path to the configuration file" do |config|
        config_file = config
      end

      parser.on "-h", "--help", "Show help" do
        puts parser
        exit
      end

      parser.invalid_option do |flag|
        STDERR.puts "ERROR: #{flag} is not a valid option."
        STDERR.puts parser
        exit(1)
      end
    end

    load_config(config_file)
  end

  # Load the configuration file into a SchedOptions struct
  def self.load_config(config_file : String)
    if File.exists?(config_file)
      Sched.options = SchedOptions.from_yaml(File.read(config_file))
      Sched.options.load_env # ENV vars can override config options
    else
      LOG.warn("Config file #{config_file} not found. Using default options.")
    end
  rescue e
    LOG.error("Failed to load config file: #{e}")
    exit(1)
  end

  def self.initialize_scheduler
    create_secrets_yaml("scheduler")
    do_local_pack
  end

  # Start background tasks
  def self.start_background_tasks
    spawn Sched.instance.dispatch_worker
  end

  # Start the Kemal server using the configuration
  def self.start_kemal_server
    Kemal.run(ENV["NODE_PORT"].to_i32)
  end

  # Main entry point for the scheduler
  def self.run
    parse_options

    initialize_scheduler
    start_background_tasks
    start_kemal_server
  rescue e
    LOG.error(e)
  end
end

# Graceful shutdown handling
Signal::INT.trap do
  Sched.instance.shutdown
  Kemal.stop
end

# Run the scheduler
Scheduler.run
