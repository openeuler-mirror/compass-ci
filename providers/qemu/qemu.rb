#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require 'open-uri'
require 'json'
require 'set'
require 'fileutils'
require 'yaml'
require 'rest-client'

class QemuManager
  def initialize(message)
    @hostname = message["hostname"]
    @ipxe_script = message['ipxe_script']
    @is_remote = ENV["is_remote"] == 'true'
    @log_file = ENV["log_file"]
    @logger = Logger.new(@log_file)
  end

  def start_qemu_instance
    setup_working_directory(@hostname) do |host_dir|
      mac_address = generate_mac_address(@hostname)
      setup_network_files(mac_address)

      job_config, host_config_path = prepare_job_configuration(@hostname)
      return unless job_config

      run_virtual_machine(job_config, mac_address)
    end
  end

  private

  def setup_working_directory(hostname)
    host_dir = "#{ENV["HOSTS_DIR"]}/#{hostname}"
    FileUtils.rm_rf(host_dir) if Dir.exist?(host_dir)
    Dir.mkdir(host_dir)

    Dir.chdir(host_dir) do
      yield host_dir
    end
  end

  def generate_mac_address(hostname)
    `echo #{hostname} | md5sum`.chomp.gsub(/^(\w\w)(\w\w)(\w\w)(\w\w)(\w\w).*/, '0a-\1-\2-\3-\4-\5')
  end

  def setup_network_files(mac_address)
    File.write('mac', mac_address)
    File.write('ip.sh', "arp -n | grep #{mac_address.gsub('-', ':')}")
    File.chmod(0755, 'ip.sh')
  end

  def prepare_job_configuration
    return nil unless validate_job_availability
    write_ipxe_script

    job_hash = extract_job_parameters
    host_config_path = determine_host_config_path(job_hash)

    [job_hash, host_config_path]
  end

  def write_ipxe_script(content)
    File.open('ipxe_script', 'w') { |f| f.puts content }
  end

  def validate_job_availability
    if @ipxe_script.match?('No job now')
      @logger.info('No job now')
      sleep(5)
      return false
    end
    true
  end

  def extract_job_parameters
    append, initrds, kernel = parse_ipxe_script
    extract_job_metadata

    job_hash = YAML.load_file('lkp/scheduled/job_vm.yaml')
    job_hash.merge!(
      'append' => append,
      'initrds' => initrds,
      'kernel' => kernel
    )

    set_default_resources(job_hash)
    job_hash
  end

  def parse_ipxe_script
    append = initrds = kernel = ''

    @ipxe_script.each_line do |line|
      parts = line.split
      case parts[0]
      when 'initrd'
        handle_initrd(parts, initrds)
      when 'kernel'
        kernel, append = handle_kernel(parts)
      end
    end

    [append, initrds, kernel]
  end

  def handle_initrd(parts, initrds)
    file = File.basename(parts[1])
    if file == 'job.cgz'
      job_id = File.basename(File.dirname(parts[1]))
      File.write('job_id', job_id.to_s)
    end
    download_resource(parts[1])
    initrds + "#{file} "
  end

  def handle_kernel(parts)
    kernel = File.basename(parts[1])
    download_resource(parts[1])
    append = parts.drop(2).join(' ').gsub(/ initrd=[^ ]+/, '')
    [kernel, append]
  end

  def download_resource(url)
    system("wget --timestamping -nv -a #{@log_file} #{url}")
  end

  def extract_job_metadata
    `gzip -dc job.cgz | cpio -div`
    `grep -E "nr_|memory|minimum|group|RESULT_WEBDAV|result_root" lkp/scheduled/job.yaml | sed 's/^ *//' > lkp/scheduled/job_vm.yaml`
  end

  def set_default_resources(job_hash)
    job_hash['cpu_minimum'] ||= job_hash['nr_cpu']
    job_hash['memory_minimum'] ||= job_hash['memory']
  end

  def determine_host_config_path(job_hash)
    "#{ENV['LKP_SRC']}/hosts/vm-#{job_hash['cpu_minimum'].to_i.to_s}p#{job_hash['memory_minimum'].to_i.to_s}g"
  end

  def run_virtual_machine(job_hash, mac_address, host_config_path)
    return unless File.exist?(host_config_path)

    host_config = load_host_configuration(host_config_path)
    env_vars = prepare_env(job_hash, host_config, mac_address)

    execute_virtual_machine(env_vars)
    upload_dmesg(job_hash) if job_hash['id']
  end

  def load_host_configuration(config_path)
    YAML.load_file(config_path)
  end

  def prepare_env(job_hash, host_config, mac_address)
    env_vars = job_hash.merge(host_config)
    env_vars.transform_values! do |v|
      case v
      when Integer then v.to_s
      when Array then v.join(' ')
      else v
      end
    end
    env_vars.merge!(
      'mac' => mac_address,
      'hostname' => @hostname
    )
  end

  def execute_virtual_machine(env_vars)
    system(
      env_vars,
      "#{ENV['CCI_SRC']}/providers/qemu/kvm.sh"
    )
  end

  def upload_dmesg(config)
    upload_url = if @is_remote
      "#{config["RESULT_WEBDAV_HOST"]}:#{config["RESULT_WEBDAV_PORT"]}#{config["result_root"]}/dmesg"
    else
      "http://#{config["RESULT_WEBDAV_HOST"]}:#{config["RESULT_WEBDAV_PORT"]}#{config["result_root"]}/dmesg"
    end

    %x(curl -sSf -F "file=@#{@log_file}" #{upload_url} --cookie "JOBID=#{config["id"]}")
  end
end
