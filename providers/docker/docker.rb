#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'open-uri'
require 'json'
require 'set'
require 'fileutils'
require_relative '../../container/defconfig'

BASE_DIR = '/srv/dc'

names = Set.new %w[
  SCHED_HOST
  SCHED_PORT
]
defaults = relevant_defaults(names)
SCHED_HOST = defaults['SCHED_HOST'] || '172.17.0.1'
SCHED_PORT = defaults['SCHED_PORT'] || 3000

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

def parse_response(url)
  response = nil
  URI.open(url) do |http|
    response = http.read
  end
  hash = response.is_a?(String) ? JSON.parse(response) : nil
  if hash.nil? || !hash.key?('job')
    puts '..........'
    puts 'no job now'
    puts '..........'
    return nil
  end
  return hash
end

def wget_cmd(path, url, name)
  system "wget -q -P #{path} #{url} && gzip -dc #{path}/#{name} | cpio -id -D #{path}"
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
  wget_cmd(load_path, job_url, 'job.cgz')
  wget_cmd(load_path, lkp_url, "lkp-#{arch}.cgz")
end

def start_container(hostname, load_path, hash)
  docker_image = hash['docker_image']
  system "#{ENV['CCI_SRC']}/sbin/docker-pull #{docker_image}"
  system(
    { 'hostname' => hostname, 'docker_image' => docker_image, 'load_path' => load_path },
    ENV['CCI_SRC'] + '/providers/docker/run.sh'
  )
  clean_dir(load_path)
end

def main(hostname, queues)
  set_host2queues(hostname, queues)
  url = get_url hostname
  puts url
  hash = parse_response url
  return del_host2queues(hostname) if hash.nil?

  load_path = build_load_path(hostname)
  load_initrds(load_path, hash)
  start_container(hostname, load_path, hash)
  del_host2queues(hostname)
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

def save_pid(pids)
  FileUtils.cd("#{ENV['CCI_SRC']}/providers")
  f = File.new('dc.pid', 'a')
  f.puts pids
  f.close
end

def multi_docker(hostname, nr_container, queues)
  pids = []
  nr_container.to_i.times do |i|
    pid = Process.fork do
      loop_main("#{hostname}-#{i}", queues)
    end
    pids << pid
  end
  return pids
end
