#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'open-uri'
require 'json'
require 'set'
require 'fileutils'
require 'yaml'
require 'rest-client'

class DockerManager
  attr_accessor :host_dir, :log_file, :is_remote, :message, :hostname

  CPIO_PATTERN_FILE = "/tmp/docker_cpio_pattern.txt"

  def initialize(message)
    @message = message
    @hostname = message["hostname"]
    @host_dir = ENV["host_dir"]
    @log_file = ENV["log_file"]
    @is_remote = ENV["is_remote"] == 'true'
  end

  def download_extract_cpio(path, url, name)
    File.write(CPIO_PATTERN_FILE, "lkp*") unless File.exist? CPIO_PATTERN_FILE

    cmd = %W(curl -sS --create-dirs -o #{path}/#{name} #{url})
    # puts cmd.join(" ")

    system(*cmd) &&
    system(%Q(gzip -dc #{path}/#{name} | cpio -idu --quiet -D #{path} --pattern-file=#{CPIO_PATTERN_FILE}))
  end

  def load_initrds
    initrds = JSON.parse(@message['initrds'])
    record_log(initrds)
    initrds.each do |initrd|
      return false unless download_extract_cpio(@host_dir, initrd, initrd.to_s.sub(/.*:\/\//, ""))
    end
    true
  end

  def load_package_optimization_strategy
    job_yaml = "#{@host_dir}/lkp/scheduled/job.yaml"
    job_info = YAML.load_file(job_yaml)
    cpu_minimum = job_info['cpu_minimum'].to_s
    memory_minimum = job_info['memory_minimum'].to_s
    bin_shareable = job_info['bin_shareable'].to_s
    ccache_enable = job_info['ccache_enable'].to_s

    need_docker_sock = 'n'
    if job_info.has_key?('build_mini_docker')
      need_docker_sock = 'y'
    end

    return cpu_minimum, memory_minimum, bin_shareable, ccache_enable, need_docker_sock
  end

  def start_container
    docker_image = @message['docker_image']
    system "#{ENV['CCI_SRC']}/sbin/docker-pull #{docker_image}"
    cpu_minimum, memory_minimum, bin_shareable, ccache_enable, need_docker_sock = load_package_optimization_strategy
    system(
      { 'job_id' => @message['job_id'],
        'cpu_minimum' => "#{cpu_minimum}",
        'memory_minimum' => "#{memory_minimum}",
        'bin_shareable' => "#{bin_shareable}",
        'ccache_enable' => "#{ccache_enable}",
        'need_docker_sock' => "#{need_docker_sock}",
        'hostname' => @hostname,
        'docker_image' => docker_image,
        'nr_cpu' => @message['nr_cpu'],
        'memory' => @message['memory'],
        'os' => @message['os'],
        'osv' => @message['osv'],
        'result_root' => @message['result_root'],
        'host_dir' => @host_dir,
        'log_file' => @log_file },
      ENV['CCI_SRC'] + '/providers/docker/run.sh'
    )
  end

  def record_log(list)
    File.open(@log_file, 'a') do |f|
      list.each do |line|
        f.puts line
      end
    end
  end

  def record_startup_log
    start_time = Time.new
    File.open(@log_file, 'w') do |f|
      # fluentd refresh time is 1s
      # let fluentd to monitor this file first
      sleep(2)

      f.puts "\n#{start_time.strftime('%Y-%m-%d %H:%M:%S')} starting DOCKER"
      f.puts "\n#job_id={@message['job_id']}"
    end
    return start_time
  end

  def record_end_log(start_time)
    duration = ((Time.new - start_time) / 60).round(2)
    File.open(@log_file, 'a') do |f|
      f.puts "\nTotal DOCKER duration:  #{duration} minutes"
    end
  end

  def get_job_info
    return {} unless File.exist?("#{@host_dir}/lkp/scheduled/job.yaml")
    YAML.load_file("#{@host_dir}/lkp/scheduled/job.yaml")
  end

  def start_container_instance
    if Dir.exist?(@host_dir)
      FileUtils.rm_rf(@host_dir)
    end
    FileUtils.mkdir_p(@host_dir + "/result_root")

    start_time = record_startup_log

    return unless load_initrds
    job_info = get_job_info

    start_container

    record_end_log(start_time)

    # Allow fluentd sufficient time to read the contents of the log file
    sleep(5)
  ensure
    record_log(["finished the docker"])
  end
end
