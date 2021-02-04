# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'libvirt'

# connect libvirt daemon
class LibvirtConnect
  def initialize
    @conn = Libvirt.open('qemu:///system')
  end

  def define(xml)
    @dom = @conn.define_domain_xml(File.read(xml))
  end

  def create
    @dom.create
  end

  def wait
    loop do
      sleep 10
      break unless @dom.active?
    end
  end

  def close
    @conn.close
  end
end
