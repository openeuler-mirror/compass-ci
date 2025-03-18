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

  def initialize(message)
    @message = message
    @hostname = message["hostname"]
    @host_dir = ENV["host_dir"]
    @log_file = ENV["log_file"]
    @is_remote = ENV["is_remote"] == 'true'
  end

  def download_initrds
    initrds = JSON.parse(@message['initrds'])
    local_files = []
    initrds.each do |initrd|
      local_files << download_resource(initrd)
    end
    local_files
  end

  def start_container_instance
    download_initrds
    docker_image = @message['docker_image']
    system "#{ENV['CCI_SRC']}/sbin/docker-pull #{docker_image}"
    env =  { 'job_id' => @message['job_id'],
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
    env["cpu_minimum"] = @message["cpu_minimum"] if @message.include? "cpu_minimum"
    env["memory_minimum"] = @message["memory_minimum"] if @message.include? "memory_minimum"
    env["ccache_enable"] = @message["ccache_enable"] if @message.include? "ccache_enable"
    env["bin_shareable"] = @message["bin_shareable"] if @message.include? "bin_shareable"
    env["build_mini_docker"] = @message["build_mini_docker"] if @message.include? "build_mini_docker"
    exec(env, ENV['CCI_SRC'] + '/providers/docker/run.sh')
  end

end
