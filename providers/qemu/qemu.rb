#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require 'logger'
require 'open3'
require 'yaml'
require 'socket'
require 'fileutils'
require 'shellwords'

class QemuManager
  class ConfigurationError < StandardError; end
  class ResourceError < StandardError; end

  def initialize(message)
    validate_environment_variables
    @hostname = message["hostname"].to_s
    @ipxe_script = message['ipxe_script'].to_s
    @job_id = message['job_id'].to_s
    @logger = setup_logger
    validate_initial_parameters
  end

  def start_qemu_instance
    Dir.chdir(ENV["host_dir"]) do
      job_config = prepare_job_configuration
      return unless job_config

      env_vars = prepare_environment(job_config)

      # @logger.info("Starting QEMU instance with config:\n#{env_vars.to_yaml}")
      execute_virtual_machine(env_vars)
    end
  rescue Errno::ENOENT => e
    @logger.error("File operation failed: #{e.message}")
    raise
  rescue StandardError => e
    @logger.error("Critical error: #{e.message}")
    raise
  end

  private

  def validate_environment_variables
    %w[LKP_SRC CCI_SRC host_dir].each do |var|
      next if ENV[var]

      raise ConfigurationError, "Missing required environment variable: #{var}"
    end
  end

  def validate_initial_parameters
    raise ArgumentError, "Missing hostname" if @hostname.empty?
    raise ArgumentError, "Empty iPXE script" if @ipxe_script.empty?
  end

  def setup_logger
    Logger.new(ENV["log_file"] || $stdout).tap do |logger|
      logger.formatter = proc do |severity, datetime, _progname, msg|
        "#{datetime} [#{severity}] #{msg}\n"
      end
    end
  end

  def generate_consistent_mac_address(hostname)
    digest = Digest::MD5.hexdigest(hostname)
    raise ResourceError, "Invalid MAC generation" if digest.size < 12

    "0a-#{digest[0..1]}-#{digest[2..3]}-#{digest[4..5]}-#{digest[6..7]}-#{digest[8..9]}"
  end

  def validate_job_availability
    if @ipxe_script.include?('No job now')
      # @logger.info('No jobs available in iPXE script')
      sleep(5)
      false
    else
      true
    end
  end

  def prepare_job_configuration
    return unless validate_job_availability

    write_file_with_validation('ipxe_script', @ipxe_script)
    @append, @initrds, @kernel = parse_download_ipxe
    extract_job
    job_hash = load_job_metadata
  end

  def write_file_with_validation(filename, content)
    File.write(filename, content)
    raise ResourceError, "Failed to write #{filename}" unless File.exist?(filename)
  end

  # Example ipxe_script content:
  # ```
  # #!ipxe
  #
  # initrd http://172.17.0.1:3000/srv/initrd/osimage/openeuler/x86_64/20.03/20210609.0.cgz
  # initrd http://172.17.0.1:3000/srv/os/openeuler/x86_64/20.03/boot/modules-4.19.90-2003.4.0.0036.oe1.x86_64.cgz
  # initrd http://172.17.0.1:3000/srv/initrd/osimage/openeuler/x86_64/20.03/run-ipconfig.cgz
  # initrd http://172.17.0.1:3000/srv/file-store/lkp_src/base/2025-02-28/032123d325bdca9b333c2040e34504c3009fb9a4.cgz
  # initrd http://172.17.0.1:3000/srv/file-store/lkp_src/delta/2025-02-28/032123d325bdca9b333c2040e34504c3009fb9a4-95f40ff66011da528978c3f56d9d07a8.cgz
  # initrd http://172.17.0.1:3000/srv/scheduler/pending-jobs/25030310160812300/job.cgz
  # kernel http://172.17.0.1:3000/srv/os/openeuler/x86_64/20.03/boot/vmlinuz-4.19.90-2003.4.0.0036.oe1.x86_64 user=lkp job=/lkp/scheduled/job.yaml ip=dhcp rootovl ro rdinit=/sbin/init prompt_ramdisk=0 console=tty0 console=ttyS0,115200  initrd=20210609.0.cgz  initrd=modules-4.19.90-2003.4.0.0036.oe1.x86_64.cgz  initrd=run-ipconfig.cgz  initrd=032123d325bdca9b333c2040e34504c3009fb9a4.cgz  initrd=032123d325bdca9b333c2040e34504c3009fb9a4-95f40ff66011da528978c3f56d9d07a8.cgz  initrd=job.cgz rootfs_disk=/dev/vda
  # echo ipxe will boot job id=25030310160812300, ip=${ip}, mac=${mac}
  # echo result_root=/result/boot/2025-03-03/vm/openeuler-20.03-x86_64/1/25030310160812300
  #
  # boot
  # ```
  def parse_download_ipxe
    append = ''
    initrds = []
    kernel = ''

    @ipxe_script.each_line do |line|
      line.strip!
      next if line.start_with?('#') || line.empty?

      case line
      when /^initrd\s+(\S+)/
        handle_initrd_line(Regexp.last_match(1), initrds)
      when /^kernel\s+(\S+)(.*)/
        kernel, append = handle_kernel_line(Regexp.last_match(1), Regexp.last_match(2))
      end
    end

    [append.freeze, initrds.freeze, kernel.freeze]
  end

  def handle_initrd_line(url, initrds)
    # @logger.info("Processing initrd: #{url}")
    initrds << download_resource(url)
  end

  def handle_kernel_line(url, parameters)
    # @logger.info("Processing kernel: #{url}")
    kernel = download_resource(url)
    append = parameters.gsub(/\s+initrd=\S+/, '').strip
    append += " console=ttyS1,115200"  # 2nd serial for console on unix socket

    [kernel, append]
  end

  def download_resource(url)
    # Extract the path from the URL
    if url =~ /\/job.cgz$/
      local_path = "job.cgz" # no need caching
    else
      local_path = "#{ENV["DOWNLOAD_DIR"]}#{URI.parse(url).path}"
    end

    # Skip download if the file already exists
    if File.exist?(local_path)
      # @logger.info("File already exists: #{local_path}")
      return local_path
    end

    # Create the directory structure if it doesn't exist
    FileUtils.mkdir_p(File.dirname(local_path))

    # Download the file with wget
    success = system("wget --timeout=30 --tries=3 -nv -a #{ENV['log_file'].shellescape} -O #{local_path.shellescape} #{url.shellescape}")

    # Raise an error if the download fails
    raise ResourceError, "Failed to download #{url}" unless success

    return local_path
  end

  def extract_job
    raise ResourceError, "Missing job.cgz" unless File.exist?('job.cgz')

    output, status = Open3.capture2e('gzip -dc job.cgz | cpio -di --quiet')
    raise ResourceError, "Failed to extract job.cgz: #{output}" unless status.success?
  end

  def load_job_metadata
    # Load the original job.yaml file
    job_data = YAML.safe_load(File.read('lkp/scheduled/job.yaml'))
    
    env = job_data.delete('hw') || {}

    %w[nr_cpu memory os osv].each do |k|
      env[k] = job_data[k] if job_data[k]
    end

    return env
  rescue Psych::SyntaxError => e
    raise ResourceError, "Invalid YAML format in job.yaml: #{e.message}"
  rescue Errno::ENOENT => e
    raise ResourceError, "File not found: #{e.message}"
  end

  def prepare_environment(job_config)
    env_vars = job_config.transform_values do |value|
      case value
      when Integer then value.to_s
      when Array then value.join(' ')
      else value.to_s
      end
    end

    env_vars.merge(
      'job_id' => @job_id,
      'append' => @append,
      'initrds' => @initrds.join(' '),
      'kernel' => @kernel,
      'mac' => generate_consistent_mac_address(@hostname),
      'hostname' => @hostname,
    )
  end

  def execute_virtual_machine(env_vars)
    Kernel.exec(
      env_vars,
      "#{ENV['CCI_SRC']}/providers/qemu/kvm.sh"
    )
  rescue Errno::ENOENT => e
    raise ResourceError, "Failed to execute kvm.sh: #{e.message}"
  end
end
