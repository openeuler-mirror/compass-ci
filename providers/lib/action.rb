# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

# expand each element of the domain.xml
module Action
  TEMPLATE_DIR = "#{ENV['CCI_SRC']}/providers/libvirt/templates"
  def expand_erb(file)
    @context.expand_erb(File.read(file))
  end

  def domain
    @doc = Nokogiri::XML(expand_erb(@domain_option))
  end

  def name
    @doc.xpath('//domain/name').remove
    @doc.root.add_child expand_erb("#{TEMPLATE_DIR}/name.xml")
  end

  def os
    @doc.xpath('//domain/os').remove
    @doc.root.add_child expand_erb("#{TEMPLATE_DIR}/os.xml")
  end

  def emulator
    @doc.xpath('//domain/devices/emulator').remove
    @doc.xpath('//domain/devices')[0].add_child expand_erb("#{TEMPLATE_DIR}/emulator.xml")
  end

  def cpu
    @doc.root.add_child expand_erb("#{TEMPLATE_DIR}/cpu.xml")
  end

  def memory
    @doc.xpath('//domain/memory').remove
    @doc.xpath('//domain/currentMemory').remove
    @doc.xpath('//domain/maxMemory').remove
    @doc.root.add_child expand_erb("#{TEMPLATE_DIR}/memory.xml")
  end

  def devices
    @doc.root.add_child expand_erb("#{TEMPLATE_DIR}/devices.xml")
  end

  def disk
    @context.info['disk'] ||= nil
    @doc.xpath('//domain/devices')[0].add_child expand_erb("#{TEMPLATE_DIR}/disk.xml")
  end

  def serial
    @doc.xpath('//domain/devices/serial').remove
    @doc.xpath('//domain/devices')[0].add_child expand_erb("#{TEMPLATE_DIR}/serial.xml")
  end

  def interface
    @doc.xpath('//domain/devices/interface').remove
    @doc.xpath('//domain/devices')[0].add_child expand_erb("#{TEMPLATE_DIR}/interface.xml")
  end

  def active
    @doc.xpath('//domain/on_poweroff').remove
    @doc.xpath('//domain/on_reboot').remove
    @doc.xpath('//domain/on_crash').remove
    @doc.root.add_child expand_erb("#{TEMPLATE_DIR}/active.xml")
  end

  def clock
    @doc.root.add_child expand_erb("#{TEMPLATE_DIR}/clock.xml")
  end

  def seclabel
    @doc.root.add_child expand_erb("#{TEMPLATE_DIR}/seclabel.xml")
  end
end
