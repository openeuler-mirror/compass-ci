# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'set'
require 'nokogiri'
require 'yaml'
require_relative 'action'
require_relative "#{ENV['LKP_SRC']}/lib/hashugar"

# generate a domain.xml
class Domain
  include Action

  TEMPLATE_DIR = "#{ENV['CCI_SRC']}/providers/libvirt/templates"
  OPTION_FILE = "#{TEMPLATE_DIR}/options.yaml"
  def initialize(context, logger)
    @doc = nil
    @context = context
    @logger = logger
    @options = Hashugar.new(YAML.safe_load(File.read(OPTION_FILE)))
  end

  def generate
    domain_option
    if user_domain?
      default_option
      return
    end
    replaceable_option
    default_option
  end

  def save_to(filename)
    File.open(filename, 'w') do |f|
      f.puts @doc.to_xml
    end
    File.realpath(filename)
  end

  private

  def user_domain?
    @context.info['vt'].key?('domain')
  end

  def load_xml_file(filepath)
    host = @context.info['SRV_HTTP_HOST']
    port = @context.info['SRV_HTTP_PORT']
    system "wget --timestamping --progress=bar:force http://#{host}:#{port}/cci/libvirt-xml/#{filepath}"
    %x(basename #{filepath}).chomp
  end

  def domain_option
    @domain_option = "#{TEMPLATE_DIR}/#{@options.domain}.xml"
    if user_domain?
      @domain_option = load_xml_file(@context.info['vt']['domain'])
    end
    @logger.info("Domain option: #{@domain_option}")
    domain
  end

  def default_option
    @options.default.each do |one|
      instance_eval one
    end
  end

  def replaceable_option
    @options.replaceable.each do |one|
      instance_eval one
    end
  end
end
