# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'rest-client'
require_relative 'constants'

# sched client class
class SchedClient
  def initialize(host = SCHED_HOST, port = SCHED_PORT)
    @host = host
    @port = port
  end

  def submit_job(job_json)
    resource = RestClient::Resource.new("http://#{@host}:#{@port}/submit_job")
    resource.post(job_json)
  end

  # scheduler API /boot.:boot_type/:parameter/:value
  #     boot_type parameter
  # 1   ipxe      mac
  # 2   container hostname
  # 3   libvirt   mac
  def consume_job(boot_type, parameter, value)
    RestClient.get "http://#{@host}:#{@port}/boot.#{boot_type}/#{parameter}/#{value}"
  end

  def register_mac2host(hostname, mac)
    RestClient.put(
      "http://#{@host}:#{@port}/set_host_mac?hostname=#{hostname}&mac=#{mac}", {}
    )
  end

  def register_host2queues(hostname, queues)
    RestClient.put(
      "http://#{@host}:#{@port}/set_host2queues?host=#{hostname}&queues=#{queues}", {}
    )
  end

  def delete_mac2host(mac)
    RestClient.put(
      "http://#{@host}:#{@port}/del_host_mac?mac=#{mac}", {}
    )
  end

  def delete_host2queues(hostname)
    RestClient.put(
      "http://#{@host}:#{@port}/del_host2queues?host=#{hostname}", {}
    )
  end
end
