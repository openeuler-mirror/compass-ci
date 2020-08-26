#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require_relative 'dc-image'

OS_PATH ||= ENV['OS_PATH'] || '/os/'

# Parse the parameters and make use of them
class ParseParam
  attr_reader :dc_name, :local_dc_img

  def initialize(rootdir)
    _, _, @os_name, _, @os_version = rootdir.split('/')
    @dc_name = "dc-#{@os_name}-#{@os_version}"
  end

  def prepare_env
    @hub_dc_img = get_hub_dc_image(@os_name, @os_version)
    @local_dc_img = get_local_dc_image(@os_name, @os_version)
    prepare_dc_images(@local_dc_img, @hub_dc_img)
  end
end

def check_argv(argv)
  usage(argv)
  rootfs_dir = OS_PATH + argv[0]
  raise 'Wrong vmlinuz path' unless File.exist?(rootfs_dir + '/vmlinuz')

  return rootfs_dir
end

def usage(argv)
  return if argv.size > 1

  raise "Example usages:
./run centos/aarch64/7.6 package1 package2 ...
./run centos/aarch64/7.6 $(show-depends-packages centos)
centos is an example adaption file contain packages mapping from debian to centos.
The whole path is '$LKP_SRC/distro/adaptation/centos'."
end

def get_packages(argv)
  argv.shift
  return argv.join(' ')
end
