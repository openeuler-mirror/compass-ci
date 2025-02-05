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
require_relative '../../lib/mq_client'
require_relative '../../container/defconfig'

BASE_DIR = '/srv/dc'
job_info = {}

names = Set.new %w[
  SCHED_HOST
  SCHED_PORT
  MQ_HOST
  MQ_PORT
  DOMAIN_NAME
]

defaults = relevant_defaults(names)
SCHED_HOST = ENV['SCHED_HOST'] || ENV['LKP_SERVER'] || defaults['SCHED_HOST'] || '172.17.0.1'
SCHED_PORT = ENV['SCHED_HOST'] || ENV['LKP_CGI_PORT'] ||defaults['SCHED_PORT'] || 3000

LOG_DIR = '/srv/cci/serial/logs'
Dir.mkdir(LOG_DIR) unless File.exist?(LOG_DIR)

MQ_HOST = ENV['MQ_HOST'] || ENV['LKP_SERVER'] || defaults['MQ_HOST'] || 'localhost'
MQ_PORT = ENV['MQ_PORT'] || defaults['MQ_PORT'] || 5672
DOMAIN_NAME = defaults['DOMAIN_NAME']

HOST_MACHINE = ENV["HOSTNAME"]
ARCH = get_arch

def get_url(hostname, left_mem, is_remote)
  common = "ws/boot.container?hostname=#{hostname}&left_mem=#{left_mem}&tbox_type=dc&is_remote=#{is_remote}&host_machine=${HOST_MACHINE}&arch=#{ARCH}"
  if is_remote == 'true'
    "wss://#{DOMAIN_NAME}/#{common}"
  else
    "ws://#{SCHED_HOST}:#{SCHED_PORT}/#{common}"
  end
end

def parse_response(url, hostname, is_remote)
  log_file = "#{LOG_DIR}/#{hostname}"
  record_start_log(log_file, hash: {"#{hostname}"=> "start the docker"})
  record_log(log_file, ["ws boot start"])
  response = ws_boot(url, hostname, is_remote)
  record_log(log_file, [response])
  hash = response.is_a?(String) ? JSON.parse(response) : {}
  return nil if hash['job_id'] == '0'

  unless hash.key?('initrds')
    puts response
    return nil
  end
  return hash
end

def curl_cmd(path, url, name)
  %x(curl -sS --create-dirs -o #{path}/#{name} #{url} && gzip -dc #{path}/#{name} | cpio -idu -D #{path})
end

def build_load_path(hostname)
  return BASE_DIR + '/' + hostname
end

def clean_dir(path)
  Dir.foreach(path) do |file|
    if file != '.' && file != '..'
      filename = File.join(path, file)
      if File.directory?(filename)
        FileUtils.rm_r(filename)
      else
        File.delete(filename)
      end
    end
  end
end

def load_initrds(load_path, hash, log_file)
  clean_dir(load_path) if Dir.exist?(load_path)
  initrds = JSON.parse(hash['initrds'])
  record_log(log_file, initrds)
  initrds.each do |initrd|
    curl_cmd(load_path, initrd, initrd.to_s)
  end
end

def load_package_optimization_strategy(load_path)
  job_yaml = load_path + "/lkp/scheduled/job.yaml"
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

def start_container(hostname, load_path, hash)
  docker_image = hash['docker_image']
  system "#{ENV['CCI_SRC']}/sbin/docker-pull #{docker_image}"
  cpu_minimum, memory_minimum, bin_shareable, ccache_enable, need_docker_sock = load_package_optimization_strategy(load_path)
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
      'load_path' => load_path,
      'log_dir' => "#{LOG_DIR}/#{hostname}" },
    ENV['CCI_SRC'] + '/providers/docker/run.sh'
  )
  clean_dir(load_path)
end

def record_log(log_file, list)
  File.open(log_file, 'a') do |f|
    list.each do |line|
      f.puts line
    end
  end
end

def record_start_log(log_file, hash: {})
  start_time = Time.new
  File.open(log_file, 'w') do |f|
    # fluentd refresh time is 1s
    # let fluentd to monitor this file first
    sleep(2)
    f.puts "\n#{start_time.strftime('%Y-%m-%d %H:%M:%S')} starting DOCKER"
    f.puts "\n#{hash['job']}"
  end
  return start_time
end

def record_inner_log(log_file, hash: {})
  start_time = Time.new
  File.open(log_file, 'a') do |f|
    # fluentd refresh time is 1s
    # let fluentd to monitor this file first
    sleep(2)
    f.puts "\n#{start_time.strftime('%Y-%m-%d %H:%M:%S')} starting DOCKER"
    f.puts "\n#{hash['job']}"
  end
  return start_time
end

def record_end_log(log_file, start_time)
  duration = ((Time.new - start_time) / 60).round(2)
  File.open(log_file, 'a') do |f|
    f.puts "\nTotal DOCKER duration:  #{duration} minutes"
  end
  # Allow fluentd sufficient time to read the contents of the log file
  sleep(5)
end

def get_job_info(path)
  return {} unless File.exist? path
  YAML.load_file(path)
end

def upload_dmesg(job_info, log_file, is_remote)
  return if job_info.empty?
  
  if is_remote == 'true'
    upload_url = "#{job_info["RESULT_WEBDAV_HOST"]}:#{job_info["RESULT_WEBDAV_PORT"]}#{job_info["result_root"]}/dmesg"
  else
    upload_url = "http://#{job_info["RESULT_WEBDAV_HOST"]}:#{job_info["RESULT_WEBDAV_PORT"]}#{job_info["result_root"]}/dmesg"
  end
  %x(curl -sSf -F "file=@#{log_file}" #{upload_url} --cookie "JOBID=#{job_info["id"]}")
end

def main(hostname, tags, is_remote)
  puts "multi_docker status is running"
  vm_containers = check_vm_status
  return nil if vm_containers.nil?
  pre_num = vm_containers[-1].to_s
  pre_hostname = "#{hostname}-#{pre_num}"
  left_mem = get_left_memory
  url = get_url(pre_hostname, left_mem, is_remote)
  puts url
  hash = parse_response(url, pre_hostname, is_remote)
  puts hash
  return nil if hash.nil?
  if hash['memory_minimum'].nil? || hash['memory_minimum'].empty?
    hash['memory_minimum'] = '8'
  end
  # record_spec_mem(hash, pre_num, 'dc')
  thr = Thread.new do
    run_container(pre_hostname, hash, thr, is_remote)
  end
end

def run_container(hostname, hash, thr, is_remote)
  log_file = "#{LOG_DIR}/#{hostname}"
  load_path = build_load_path(hostname)
  FileUtils.mkdir_p(load_path) unless File.exist?(load_path)
  lock_file = load_path + "/#{hostname}.lock"

  start_time = record_inner_log(log_file, hash: hash)

  load_initrds(load_path, hash, log_file)
  job_info = get_job_info("#{load_path}/lkp/scheduled/job.yaml")

  start_container(hostname, load_path, hash)

  record_end_log(log_file, start_time)
  upload_dmesg(job_info, log_file, is_remote)
ensure
  record_log(log_file, ["finished the docker"])
  # release_spec_mem(hostname, hash, 'dc')
  thr.exit
end

def check_vm_status
  free_mem = get_free_memory
  rest_containers = pre_check_tbox('dc')
  if rest_containers and free_mem > 4
    return rest_containers
  else
    puts "testbox is not reday"
    return nil
  end
end

def start(hostname, tags, is_remote)
  safe_stop_file = "/tmp/#{ENV['HOSTNAME']}/safe-stop"
  mem_total = get_total_memory
  loop do
    begin
      break if File.exist?(safe_stop_file)
      main(hostname, tags, is_remote)
    rescue StandardError => e
      puts e.backtrace
      puts e
      # if an exception occurs, request the next time after 30 seconds
      sleep 25
    ensure
      sleep 5
    end
  end
end
