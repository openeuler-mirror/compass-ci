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

require_relative "../lib/jwt"
require_relative "../lib/remote_client"
require_relative '../lib/common'

# Global variables
HOST_DIR = ENV["HOST_DIR"] || "/srv/cci/hosts"
LOG_FILE = ENV["LOG_FILE"] || "/srv/cci/logs"

def curl_cmd(path, url, name)
  %x(curl -sS --create-dirs -o #{path}/#{name} #{url} && gzip -dc #{path}/#{name} | cpio -idu -D #{path})
end

def load_initrds(hash)
  initrds = JSON.parse(hash['initrds'])
  record_log(initrds)
  initrds.each do |initrd|
    curl_cmd(HOST_DIR, initrd, initrd.to_s)
  end
end

def load_package_optimization_strategy
  job_yaml = "#{HOST_DIR}/lkp/scheduled/job.yaml"
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

def start_container(hostname, hash)
  docker_image = hash['docker_image']
  system "#{ENV['CCI_SRC']}/sbin/docker-pull #{docker_image}"
  cpu_minimum, memory_minimum, bin_shareable, ccache_enable, need_docker_sock = load_package_optimization_strategy
  system(
    { 'job_id' => hash['job_id'],
      'cpu_minimum' => "#{cpu_minimum}",
      'memory_minimum' => "#{memory_minimum}",
      'bin_shareable' => "#{bin_shareable}",
      'ccache_enable' => "#{ccache_enable}",
      'need_docker_sock' => "#{need_docker_sock}",
      'hostname' => hostname,
      'docker_image' => docker_image,
      'nr_cpu' => hash['nr_cpu'],
      'memory' => hash['memory'],
      'load_path' => HOST_DIR,
      'log_file' => LOG_FILE },
    ENV['CCI_SRC'] + '/providers/docker/run.sh'
  )
end

def record_log(list)
  File.open(LOG_FILE, 'a') do |f|
    list.each do |line|
      f.puts line
    end
  end
end

def record_start_log(hash: {})
  start_time = Time.new
  File.open(LOG_FILE, 'w') do |f|
    # fluentd refresh time is 1s
    # let fluentd to monitor this file first
    sleep(2)
    f.puts "\n#{start_time.strftime('%Y-%m-%d %H:%M:%S')} starting DOCKER"
    f.puts "\n#{hash['job']}"
  end
  return start_time
end

def record_inner_log(hash: {})
  start_time = Time.new
  File.open(LOG_FILE, 'a') do |f|
    # fluentd refresh time is 1s
    # let fluentd to monitor this file first
    sleep(2)
    f.puts "\n#{start_time.strftime('%Y-%m-%d %H:%M:%S')} starting DOCKER"
    f.puts "\n#{hash['job']}"
  end
  return start_time
end

def record_end_log(start_time)
  duration = ((Time.new - start_time) / 60).round(2)
  File.open(LOG_FILE, 'a') do |f|
    f.puts "\nTotal DOCKER duration:  #{duration} minutes"
  end
  # Allow fluentd sufficient time to read the contents of the log file
  sleep(5)
end

def get_job_info
  return {} unless File.exist?("#{HOST_DIR}/lkp/scheduled/job.yaml")
  YAML.load_file("#{HOST_DIR}/lkp/scheduled/job.yaml")
end

def upload_dmesg(job_info, is_remote)
  return if job_info.empty?

  if is_remote == 'true'
    upload_url = "#{job_info["RESULT_WEBDAV_HOST"]}:#{job_info["RESULT_WEBDAV_PORT"]}#{job_info["result_root"]}/dmesg"
  else
    upload_url = "http://#{job_info["RESULT_WEBDAV_HOST"]}:#{job_info["RESULT_WEBDAV_PORT"]}#{job_info["result_root"]}/dmesg"
  end
  %x(curl -sSf -F "file=@#{LOG_FILE}" #{upload_url} --cookie "JOBID=#{job_info["id"]}")
end

def start_container_instance(message)
  hostname = message["hostname"]

  if Dir.exist?(HOST_DIR)
    FileUtils.rm_rf(HOST_DIR)
  end
  Dir.mkdir(HOST_DIR)

  start_time = record_inner_log(hash: message)

  load_initrds(message)
  job_info = get_job_info

  start_container(hostname, message)

  record_end_log(start_time)
  upload_dmesg(job_info, message["is_remote"])
ensure
  record_log(["finished the docker"])
end
