#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'open-uri'
require 'json'
require 'set'
require 'fileutils'
require_relative '../container/defconfig'

BASE_DIR = ENV['HOME'] + '/jobs'

def get_url(hostname)
  names = Set.new %w[
    SCHED_HOST
    SCHED_PORT
  ]
  defaults = relevant_defaults(names)
  host = defaults['SCHED_HOST'] || '172.17.0.1'
  port = defaults['SCHED_PORT'] || 3000
  "http://#{host}:#{port}/boot.container/hostname/#{hostname}"
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
  system "wget -P #{path} #{url} && gzip -dc #{path}/#{name} | cpio -id -D #{path}"
end

def build_load_path
  return BASE_DIR + '/' + Process.pid.to_s
end

def load_initrds(load_path, hash)
  arch = RUBY_PLATFORM.split('-')[0]
  job_url = hash['job']
  lkp_url = hash['lkp']
  wget_cmd(load_path, job_url, 'job.cgz')
  wget_cmd(load_path, lkp_url, "lkp-#{arch}.cgz")
end

def run(load_path, hash)
  docker_image = hash['docker_image']
  system "docker pull #{docker_image}"
  system(
    { 'docker_image' => docker_image, 'load_path' => load_path },
    ENV['CCI_SRC'] + '/providers/docker/run.sh'
  )
  FileUtils.rm_r(load_path)
end

def main(hostname)
  url = get_url hostname
  puts url
  hash = parse_response url
  return if hash.nil?

  load_path = build_load_path
  load_initrds(load_path, hash)
  run(load_path, hash)
end

main 'dc-1g-1' if $PROGRAM_NAME == __FILE__
