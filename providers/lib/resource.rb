# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'yaml'
require_relative "#{ENV['LKP_SRC']}/lib/hashugar"

# initializing QEMU parameters
#   qemu        libvirt
# - qemu-kvm    <emulator></emulator>
# - nr_cpu      <vcpu></vcpu>
# - memory      <memory></memory>
# - arch        <type arch=''></type>
# - log_file    <serial></serial>
# - kernel      <kernel></kernel>
# - initrd      <initrd></initrd>
# - append      <cmdline></cmdline>
class Resource
  attr_reader :info

  def initialize(hostname, logger)
    @hostname = hostname
    @logger = logger
    @info = {}
    qemu_path
    arch
    log_file
    parse_host_config
  end

  def parse_response(response)
    @response = Hashugar.new(response)
    kernel
    initrd
    cmdline
  end

  private

  def qemu_path
    @info['qemu_path'] = %x(command -v qemu-kvm).chomp
    raise 'can not find available qemu command' if @info['qemu_path'].empty?
  end

  def arch
    @info['arch'] = %x(arch).chomp
  end

  def log_file
    @info['log_file'] = "/srv/cci/serial/logs/#{@hostname}"
  end

  def parse_host_config
    host_file = "#{ENV['LKP_SRC']}/hosts/#{@hostname.split('.')[0]}"
    @info.merge!(YAML.safe_load(File.read(host_file)))
  end

  def load_file(url)
    system "wget --timestamping --progress=bar:force #{url}"
    basename = File.basename(url)
    file_size = %x(ls -s --block-size=M "#{basename}").chomp
    @logger.info("Load file size: #{file_size}")
    File.realpath(basename)
  end

  def kernel
    @info['kernel'] = load_file(@response.kernel_uri)
    @logger.info("Kernel path: #{@info['kernel']}")
  end

  def merge_initrd_files(file_list, target_name)
    return if file_list.size.zero?

    initrds = file_list.join(' ')
    system "cat #{initrds} > #{target_name}"
  end

  def initrd
    initrds_uri = @response.initrds_uri
    initrds_path = []
    initrds_uri.each do |url|
      initrds_path << load_file(url)
    end
    merge_initrd_files(initrds_path, 'initrd')
    @info['initrd'] = File.realpath('initrd')
    @logger.info("Initrd path: #{@info['initrd']}")
  end

  def cmdline
    @info['cmdline'] = @response.kernel_params
    @logger.info("Cmdline: #{@info['cmdline']}")
  end
end
