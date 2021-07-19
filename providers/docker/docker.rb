#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'open-uri'
require 'json'
require 'set'
require 'fileutils'

require_relative '../lib/common'
require_relative '../../lib/mq_client'
require_relative '../../container/defconfig'

BASE_DIR = '/srv/dc'

names = Set.new %w[
  SCHED_HOST
  SCHED_PORT
]
defaults = relevant_defaults(names)
SCHED_HOST = defaults['SCHED_HOST'] || '172.17.0.1'
SCHED_PORT = defaults['SCHED_PORT'] || 3000
LOG_DIR  = '/srv/cci/serial/logs'
MQ_HOST = ENV['MQ_HOST'] || ENV['LKP_SERVER'] || 'localhost'
MQ_PORT = ENV['MQ_PORT'] || 5672

def get_url(hostname)
  "http://#{SCHED_HOST}:#{SCHED_PORT}/boot.container/hostname/#{hostname}"
end

def set_host2queues(hostname, queues)
  cmd = "curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/set_host2queues?host=#{hostname}&queues=#{queues}'"
  system cmd
end

def del_host2queues(hostname)
  cmd = "curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/del_host2queues?host=#{hostname}'"
  system cmd
end

def parse_response(url, uuid)
  safe_stop_file = "/tmp/#{ENV['HOSTNAME']}/safe-stop"
  restart_file = "/tmp/#{ENV['HOSTNAME']}/restart/#{uuid}"

  while true do
    return nil if File.exist?(safe_stop_file)
    return nil if uuid && File.exist?(restart_file)

    response = %x(curl #{url})
    hash = response.is_a?(String) ? JSON.parse(response) : {}
    next if hash["job_id"] == "0"

    unless hash.has_key?('job')
      puts response
      return nil
    end

    return hash
  end
end


def curl_cmd(path, url, name)
  system "curl -sS --create-dirs -o #{path}/#{name} #{url} && gzip -dc #{path}/#{name} | cpio -id -D #{path}"
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

def load_initrds(load_path, hash)
  clean_dir(load_path) if Dir.exist?(load_path)
  arch = RUBY_PLATFORM.split('-')[0]
  job_url = hash['job']
  lkp_url = hash['lkp']
  curl_cmd(load_path, job_url, 'job.cgz')
  curl_cmd(load_path, lkp_url, "lkp-#{arch}.cgz")
end

def start_container(hostname, load_path, hash)
  docker_image = hash['docker_image']
  system "#{ENV['CCI_SRC']}/sbin/docker-pull #{docker_image}"
  system(
    { 'job_id' => hash['job_id'],
      'hostname' => hostname,
      'docker_image' => docker_image,
      'load_path' => load_path,
      'log_dir' => "#{LOG_DIR}/#{hostname}"
    },
    ENV['CCI_SRC'] + '/providers/docker/run.sh'
  )
  clean_dir(load_path)
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

def record_end_log(log_file, start_time)
  duration = ((Time.new - start_time) / 60).round(2)
  File.open(log_file, 'a') do |f|
    f.puts "\nTotal DOCKER duration:  #{duration} minutes"
  end
  # Allow fluentd sufficient time to read the contents of the log file
  sleep(2)
end

def main(hostname, queues, uuid = nil)
  load_path = build_load_path(hostname)
  FileUtils.mkdir_p(load_path) unless File.exist?(load_path)

  lock_file = load_path + "/#{hostname}.lock"
  f = get_lock(lock_file)

  check_mem_quota

  set_host2queues(hostname, queues)
  url = get_url hostname
  puts url
  hash = parse_response(url, uuid)
  return del_host2queues(hostname) if hash.nil?

  log_file = "#{LOG_DIR}/#{hostname}"
  start_time = record_start_log(log_file, hash: hash)

  load_initrds(load_path, hash)
  start_container(hostname, load_path, hash)

  del_host2queues(hostname)
  record_end_log(log_file, start_time)
ensure
  f&.flock(File::LOCK_UN)
  f&.close
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
  mq = MQClient.new(MQ_HOST, MQ_PORT)
  queue = mq.queue(hostname, {:durable => true})
  queue.subscribe({:block => true, :manual_ack => true}) do |info,  _pro, msg|
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
