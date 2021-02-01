# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'erb'
require_relative "#{ENV['LKP_SRC']}/lib/hashugar"

# saves the context required by expand erb templates
class Context
  attr_reader :info

  def initialize(mac, hostname, queues)
    @info = {
      'mac' => mac,
      'hostname' => hostname,
      'queues' => queues
    }
  end

  def merge!(hash)
    @info.merge!(hash)
  end

  # existing variables of @info, can be used by erb
  # @info: { 'name' => 'xxx' }
  # Templates:
  #   This is <%= name %>
  # After expanding:
  #   This is xxx
  def expand_erb(template, context_hash = {})
    @info.merge!(context_hash)
    context = Hashugar.new(@info).instance_eval { binding }
    ERB.new(template, nil, '%').result(context)
  end
end
