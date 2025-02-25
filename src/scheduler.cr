# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./constants.cr"
require "./api.cr"
require "./lib/json_logger"

require "kemal"
require "option_parser"

module Scheduler

  # Initialize the logger
  LOG = JSONLogger.new

  # Parse command-line options
  def self.parse_options
    config_files = ["./scheduler-config.yaml", SCHEDULER_CONFIG_FILE]
    OptionParser.parse do |parser|
      parser.banner = "Usage: scheduler [arguments]"

      parser.on "-c CONFIG", "--config=CONFIG", "Path to the configuration file" do |config|
        config_files = [config]
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

    load_config(config_files)
  end

  # Load the configuration file into a SchedOptions struct
  def self.load_config(config_files : Array(String))
    config_files.each do |config_file|
      if File.exists?(config_file)
        Sched.options = SchedOptions.from_yaml(File.read(config_file))
        Sched.options.load_env # ENV vars can override config options
        Sched.options.validate
        return
      end
    end
    puts "Config files #{config_files.join(" and ")} not found. Using default options."
  rescue e
    LOG.error(e)
    exit(1)
  end

  def self.create_lkp_cgz
    %w(x86_64 aarch64).each do |arch|
      cgz_path = "#{BASE_DIR}/scheduler/upload-files/lkp-tests/#{arch}/#{BASE_TAG}.cgz"
      next if File.exists? cgz_path
      puts "Preparing #{cgz_path} to run LKP tests"
      %x(#{ENV["LKP_SRC"]}/sbin/create-lkp-cgz.sh #{ENV["LKP_SRC"]} #{BASE_TAG} #{cgz_path})
    end
  end

  # Start background tasks
  def self.start_background_tasks
    spawn Sched.instance.dispatch_worker
  end

  # Start the Kemal server using the configuration
  def self.start_kemal_server
    Kemal.config.host_binding = "::" # listen on all available network interfaces, including both IPv4 and IPv6.
    Kemal.config.add_handler HTTP::CompressHandler.new
    Kemal.config.public_folder = "#{BASE_DIR}/scheduler/pending-jobs"
    Kemal.run((ENV["NODE_PORT"]? || "3000").to_i32)
  end

  # Main entry point for the scheduler
  def self.run
    parse_options

    create_lkp_cgz
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
