#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'open-uri'
require 'json'
require 'set'
require 'fileutils'
require 'yaml'

require_relative '../lib/common'
require_relative '../../lib/mq_client'
require_relative '../../container/defconfig'

BASE_DIR = '/srv/dc'
job_info = {}

names = Set.new %w[
  SCHED_HOST
  SCHED_PORT
]
defaults = relevant_defaults(names)
SCHED_HOST = defaults['SCHED_HOST'] || '172.17.0.1'
SCHED_PORT = defaults['SCHED_PORT'] || 3000

LOG_DIR = '/srv/cci/serial/logs'
Dir.mkdir(LOG_DIR) unless File.exist?(LOG_DIR)

MQ_HOST = ENV['MQ_HOST'] || ENV['LKP_SERVER'] || 'localhost'
MQ_PORT = ENV['MQ_PORT'] || 5672

def get_url(hostname)
  "ws://#{SCHED_HOST}:#{SCHED_PORT}/ws/boot.container/hostname/#{hostname}"
end

def set_host2queues(hostname, queues)
  cmd = "curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/set_host2queues?host=#{hostname}&queues=#{queues}'"
  system cmd
end

def del_host2queues(hostname)
  cmd = "curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/del_host2queues?host=#{hostname}'"
  system cmd
end

def parse_response(url, hostname, uuid, index)
  log_file = "#{LOG_DIR}/#{hostname}"
  safe_stop_file = "/tmp/#{ENV['HOSTNAME']}/safe-stop"
  restart_file = "/tmp/#{ENV['HOSTNAME']}/restart/#{uuid}"

  loop do
    return nil if File.exist?(safe_stop_file)
    return nil if uuid && File.exist?(restart_file)

    record_start_log(log_file, hash: {"#{hostname}"=> "start the docker"})
    record_log(log_file, ["ws boot start"])
    response = ws_boot(url, hostname, index)
    record_log(log_file, [response])
    hash = response.is_a?(String) ? JSON.parse(response) : {}
    next if hash['job_id'] == '0'

    unless hash.key?('initrds')
      puts response
      return nil
    end

    return hash
  end
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
  memory_minimun = job_info['memory_minimun'].to_s
  bin_shareable = job_info['bin_shareable'].to_s
  ccache_enable = job_info['ccache_enable'].to_s

  return cpu_minimum, memory_minimun, bin_shareable, ccache_enable
end

def start_container(hostname, load_path, hash)
  docker_image = hash['docker_image']
  system "#{ENV['CCI_SRC']}/sbin/docker-pull #{docker_image}"
  cpu_minimum, memory_minimun, bin_shareable, ccache_enable = load_package_optimization_strategy(load_path)
  system(
    { 'job_id' => hash['job_id'],
      'cpu_minimum' => "#{cpu_minimum}",
      'memory_minimun' => "#{memory_minimun}",
      'bin_shareable' => "#{bin_shareable}",
      'ccache_enable' => "#{ccache_enable}",
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

def main(hostname, queues, uuid = nil, index = nil)
  log_file = "#{LOG_DIR}/#{hostname}"
  load_path = build_load_path(hostname)
  FileUtils.mkdir_p(load_path) unless File.exist?(load_path)

  lock_file = load_path + "/#{hostname}.lock"

  set_host2queues(hostname, queues)
  url = get_url hostname
  puts url
  hash = parse_response(url, hostname, uuid, index)
  return del_host2queues(hostname) if hash.nil?

  start_time = record_inner_log(log_file, hash: hash)

  load_initrds(load_path, hash, log_file)

  start_container(hostname, load_path, hash)

  record_end_log(log_file, start_time)
ensure
  record_log(log_file, ["finished the docker"])
  del_host2queues(hostname)
  release_mem(hostname) unless index.to_s.empty?
end

def loop_main(hostname, queues)
  loop do
    begin
      main(hostname, queues)
    rescue StandardError => e
      puts e.backtrace
      # if an exception occurs, request the next time after 30 seconds
      sleep 25
    ensure
      sleep 5
    end
  end
end

def loop_reboot_docker(hostname)
  loop do
    begin
      reboot_docker(hostname)
    rescue StandardError => e
      puts e.backtrace
      sleep 5
    end
  end
end

def reboot_docker(hostname)
  mq = MQClient.new(hostname: MQ_HOST, port: MQ_PORT)
  queue = mq.queue(hostname, { durable: true })
  queue.subscribe({ block: true, manual_ack: true }) do |info, _pro, msg|
    Process.fork do
      puts msg
      machine_info = JSON.parse(msg)
      job_id = machine_info['job_id']
      res, msg = reboot('dc', job_id)
      report_event(machine_info, res, msg)
      mq.ack(info)
    end
  end
end

def save_pid(pids)
  FileUtils.cd("#{ENV['CCI_SRC']}/providers")
  f = File.new('dc.pid', 'a')
  f.puts pids
  f.close
end

def multi_docker(hostname, nr_container, queues)
  Process.fork do
    loop_reboot_docker(hostname)
  end

  pids = []
  nr_container.to_i.times do |i|
    pid = Process.fork do
      loop_main("#{hostname}-#{i}", queues)
    end
    pids << pid
  end
  return pids
end
