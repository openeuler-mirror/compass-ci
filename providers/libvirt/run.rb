#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'digest/md5'
require_relative "#{ENV['CCI_SRC']}/lib/log"
require_relative "#{ENV['CCI_SRC']}/lib/sched_client"
require_relative "#{ENV['CCI_SRC']}/providers/lib/context"

def create_logger(hostname)
  filename = "#{hostname}.log"
  File.delete(filename) if FileTest.exist?(filename)
  Log.new filename
end

def compute_mac(string)
  /(..)(..)(..)(..)(..)/ =~ Digest::MD5.hexdigest(string)
  "0a:#{$1}:#{$2}:#{$3}:#{$4}:#{$5}"
end

def job_exist?(response)
  flag = false
  if response['job_id'].empty?
    puts '----------'
    puts 'No job now'
    puts '----------'
    flag = true
  end
  return flag
end

def request_job(context, sched_client, logger)
  mac = context.info['mac']
  hostname = context.info['hostname']
  queues = context.info['queues']
  sched_client.register_mac2host(hostname, mac)
  sched_client.register_host2queues(hostname, queues)
  response = JSON.parse(sched_client.consume_job('libvirt', 'mac', mac))
  if job_exist?(response)
    logger.info('No job now')
    sched_client.delete_mac2host(mac)
    sched_client.delete_host2queues(hostname)
    response = nil
  end
  return response
end

def main(hostname, queues)
  logger = create_logger(hostname)
  mac = compute_mac hostname
  context = Context.new(mac, hostname, queues)
  sched_client = SchedClient.new
  response = request_job(context, sched_client, logger)
  return if response.nil?

  sched_client.delete_mac2host(mac)
  sched_client.delete_host2queues(hostname)
end
