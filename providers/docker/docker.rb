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

  def extract_cpio(local_files)
    File.write(CPIO_PATTERN_FILE, "lkp*") unless File.exist? CPIO_PATTERN_FILE

    local_files.each do |file|
      system(%Q(gzip -dc #{file} | cpio -idu --quiet --directory #{@host_dir} --pattern-file=#{CPIO_PATTERN_FILE}))
    end
  end

  def download_initrds
    initrds = JSON.parse(@message['initrds'])
    local_files = []
    initrds.each do |initrd|
      local_files << download_resource(initrd)
    end
    local_files
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

  def start_container_instance
    extract_cpio(download_initrds)
    docker_image = @message['docker_image']
    system "#{ENV['CCI_SRC']}/sbin/docker-pull #{docker_image}"
    cpu_minimum, memory_minimum, bin_shareable, ccache_enable, need_docker_sock = load_package_optimization_strategy
    env =  { 'job_id' => @message['job_id'],
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
        'log_file' => @log_file,
    }
    env["cache_dirs"] = @message["cache_dirs"] if @message.include? "cache_dirs"
    exec(env, ENV['CCI_SRC'] + '/providers/docker/run.sh')
  end

end
