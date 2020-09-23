#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'yaml'

CONTAINER_PATH = File.dirname(__dir__)

def get_hub_dc_image(os_name, os_version)
  name_map = YAML.load_file("#{CONTAINER_PATH}/config.d/hub_dc_image_name")
  tag_map = YAML.load_file("#{CONTAINER_PATH}/config.d/hub_dc_image_tag")
  return "#{name_map[os_name]}:#{tag_map[os_name + os_version]}"
end

def get_local_dc_image(os_name, os_version)
  tag_map = YAML.load_file("#{CONTAINER_PATH}/config.d/local_dc_image_tag")
  return "dc-#{os_name}:#{tag_map[os_name + os_version]}"
end

def prepare_dc_images(local_dc_image, hub_dc_image)
  puts "preparing, local_dc_image: #{local_dc_image} hub_dc_image: #{hub_dc_image}"
  find_local_image = %x(docker images #{local_dc_image})
  return if find_local_image.include?(local_dc_image.split(':')[0])

  find_hub_image = %x(docker images #{hub_dc_image})
  unless find_hub_image.include?(local_dc_image.split(':')[0])
    system "docker pull #{hub_dc_image}"
  end
  system "docker tag #{hub_dc_image} #{local_dc_image}"
end
