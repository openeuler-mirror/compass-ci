#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'set'

def cci_defaults
  hash = {}
  Dir.glob(['/etc/compass-ci/*.yaml',
            '/etc/compass-ci/defaults/*.yaml',
            '/etc/compass-ci/service/*.yaml',
            '/etc/compass-ci/accounts/*.yaml',
            '/etc/compass-ci/register/*.yaml',
            "#{ENV['HOME']}/.config/compass-ci/defaults/*.yaml"]).each do |file|
    hash.update YAML.load_file(file) || {}
  end
  hash
end

def relevant_defaults(names)
  cci_defaults.select { |k, _| names.include? k }
end

def relevant_service_authentication(names)
  file_name = '/etc/compass-ci/passwd.yaml'
  return {} unless File.exist?(file_name)

  hash = YAML.load_file(file_name) || {}
  hash.select { |k, _| names.include? k }
end

def set_local_env
  hash = cci_defaults
  hash.map { |k, v| system "export #{k}=#{v}" }
end

def docker_env(hash)
  hash.map { |k, v| ['-e', "#{k}=#{v}"] }.flatten
end

def docker_rm(container)
  res = %x(docker ps -aqf name="^#{container}$")
  return if res.empty?

  system "docker stop #{container} && docker rm -f #{container}"
end

def meminfo_hash
  YAML.load_file('/proc/meminfo')
end

def get_available_memory
  memtotal = meminfo_hash['MemTotal'].to_f / 1048576

  # set container available memory size, minimum size is 1024m, maximum size is 30720m,
  # take the middle value according to the system memory size.
  [1024, 30720, Math.sqrt(memtotal) * 1024].sort[1].to_i
end

def docker_skip_rebuild(tag)
  return if ENV['skip_build_image'] != 'true'

  exit 1 if system "docker image inspect #{tag} > /dev/null 2>&1"
end

def download_repo(repo, git_branch=nil)
  names = Set.new %w[
    GITEE_ID
    GITEE_PASSWORD
  ]

  config = relevant_service_authentication(names)
  gitee_id = config['GITEE_ID']
  gitee_password = config['GITEE_PASSWORD']

  FileUtils.rm_rf(repo) if Dir.exist?(repo)
  git_branch = `awk '/^git_branch:\s/ {print $2; exit}' /etc/compass-ci/defaults/*.yaml`.chomp if git_branch.nil?
  system "umask 022 && git clone -b #{git_branch} https://#{gitee_id}:#{gitee_password}@gitee.com/openeuler-customization/#{repo}"
end

def push_image_remote(src_tag)
  names = Set.new %w[
    DOCKER_REGISTRY_USER
    DOCKER_REGISTRY_PASSWORD
  ]
  config = relevant_service_authentication(names)

  names = Set.new %w[
    DOCKER_REGISTRY_HOST
    DOCKER_PUSH_REGISTRY_PORT
  ]
  default = relevant_defaults(names)
  
  remote_docker_hub = default['DOCKER_REGISTRY_HOST'] + ':' + default['DOCKER_PUSH_REGISTRY_PORT'].to_s
  if remote_docker_hub == "registry.kubeoperator.io:8083"
    dst_tag = remote_docker_hub + '/' + src_tag
    system "docker login #{remote_docker_hub} -u #{config['DOCKER_REGISTRY_USER']} -p #{config['DOCKER_REGISTRY_PASSWORD']}"

    system "docker tag #{src_tag} #{dst_tag}"
    system "docker push #{dst_tag}"
    system "rm -f /root/.docker/config.json"

  end
end

def start_pod
  return unless Dir.exists?("k8s")
  return if Dir.empty?("k8s")

  names = Set.new %w[
    DOCKER_REGISTRY_HOST
    DOCKER_PUSH_REGISTRY_PORT
    NAMESPACE
  ]
  default = relevant_defaults(names)
  remote_docker_hub = default['DOCKER_REGISTRY_HOST'] + ':' + default['DOCKER_PUSH_REGISTRY_PORT'].to_s
  namespace = default['NAMESPACE'] || `awk '/^NAMESPACE:\s/ {print $2; exit}' /etc/compass-ci/setup.yaml`.chomp

  if remote_docker_hub == "registry.kubeoperator.io:8083"
      system "kubectl delete -f k8s/ -n #{namespace} >/dev/null 2>&1"
      system "kubectl create -f k8s/ -n #{namespace}"
      exit 1
  end
end
