#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'open-uri'
require 'json'
require 'set'
require 'fileutils'
require_relative '../container/lab.rb'

# utility class of request boot.container interface
# and consume job by docker container
class DockerProvider; end
def DockerProvider.get_url(hostname)
  names = Set.new %w[
    SCHED_HOST
    SCHED_PORT
  ]
  defaults = relevant_defaults(names)
  host = defaults['SCHED_HOST'] || '172.17.0.1'
  port = defaults['SCHED_PORT'] || 3000
  "http://#{host}:#{port}/boot.container/hostname/#{hostname}"
end

def DockerProvider.parse_response(url)
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

def DockerProvider.load_job(base_path, url)
  load_path = base_path + '/' + Process.pid.to_s
  FileUtils.mkdir_p(load_path) unless File.exist?(load_path)
  system "wget -P #{load_path} #{url} && gzip -dc #{load_path}/job.cgz | cpio -id -D #{load_path}"
  return load_path
end

def DockerProvider.run(hash)
  base_dir = ENV['HOME'] + '/jobs'
  load_path = load_job(base_dir, hash['job'])
  docker_image = hash['docker_image']
  system "docker pull #{docker_image}"
  system(
    { 'docker_image' => docker_image, 'load_path' => load_path },
    ENV['CCI_SRC'] + '/providers/docker/run.sh'
  )
  FileUtils.rm_r(load_path)
end

def main(hostname)
  url = DockerProvider.get_url(hostname)
  puts url
  hash = DockerProvider.parse_response(url)
  return if hash.nil?

  DockerProvider.run(hash)
end

main 'dc-1g-1' if $PROGRAM_NAME == __FILE__
