#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'set'
require 'kubeclient'
require 'base64'

def initialize_kubeclient
  config = Kubeclient::Config.read(ENV['KUBECONFIG'] || File.expand_path('~/.kube/config'))
  context = config.context
  auth_options = context.auth_options
  ssl_options = context.ssl_options
  endpoint = context.api_endpoint
  Kubeclient::Client.new(
    endpoint,
    'v1',
    ssl_options: ssl_options,
    auth_options: auth_options
  )
end

def get_configmap_data(client, name, namespace)
  begin
    cm = client.get_config_map(name, namespace)
    cm.data || {}
  rescue Kubeclient::ResourceNotFoundError
    puts "ConfigMap #{name} not found in namespace #{namespace}"
    {}
  end
end

def get_secret_data(client, name, namespace)
  begin
    secret = client.get_secret(name, namespace)
    secret_data = secret.data.to_h
    secret_data.each_with_object({}) do |(k, v), h|
      h[k] = Base64.decode64(v).force_encoding('UTF-8')
    end
  rescue Kubeclient::ResourceNotFoundError
    puts "Secret #{name} not found in namespace #{namespace}"
    {}
  end
end

def init_k8s_env
  all_hash = {}
  namespace = 'ems1'
  client = initialize_kubeclient
  configmap_data = get_configmap_data(client, 'pub-env', namespace)
  all_hash.merge! configmap_data.to_h
  secret_data = get_secret_data(client, 'secrets-env', namespace)
  all_hash.merge! secret_data

  tfh = all_hash.transform_keys(&:to_s)

  keys = ["ES_HOST"]
  keys.each do |key|
    tfh[key] = client.get_service(tfh[key].split('.')[0], namespace).spec.clusterIP
  end

  yml_path = '/etc/compass-ci/init-k8s-env.yaml'
  dir_path = File.dirname(yml_path)
  if !File.exist?(yml_path)
    FileUtils.mkdir_p(dir_path) unless File.directory?(dir_path)
    File.write(yml_path, tfh.to_yaml)
  end
end

init_k8s_env
