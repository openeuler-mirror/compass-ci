#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - hostname

require 'open-uri'
require 'json'
require 'set'
require 'fileutils'
require 'yaml'
require 'rest-client'

require_relative 'lib/jwt'
require_relative 'lib/remote_client'
require_relative 'lib/common'
require_relative '../container/defconfig'

is_remote = ENV["is_remote"] == 'true' ? true : false
DOMAIN_NAME = defaults['DOMAIN_NAME']

HOSTNAME = ENV["hostname"]
LOG_FILE = ENV["log_file"]
LOGGER = Logger.new(LOG_FILE)

def parse_response(url, hostname, ipxe_script_path)
  puts "multi-qemu in running..."

  LOGGER.info "Starting qemu for #{hostname}"
  LOGGER.info "Ws boot start"

  begin
    ipxe_script_content = File.read(ipxe_script_path)

    if ipxe_script_content.match? 'No job now'
      LOGGER.info 'No job now'

      puts "No job now, waiting for next job requestion(5s)"
      sleep(5)

      return false
    end

    return true
  rescue StandardError => e
    puts e
    puts e.message
  end
end

def start_qemu_instance(message)
  hostname_with_seq = message['hostname']

  host_dir = "#{ENV["HOSTS_DIR"]}/#{hostname_with_seq}"

  if Dir.exist? host_dir
    FileUtils.rm_rf(host_dir)
  end
  Dir.mkdir(host_dir)

  Dir.chdir(host_dir)
  ipxe_script_path="#{host_dir}/ipxe_script"

  mac = `echo #{hostname_with_seq} | md5sum`.chomp.gsub(/^(\w\w)(\w\w)(\w\w)(\w\w)(\w\w).*/, '0a-\1-\2-\3-\4-\5')

  puts "hostname: #{hostname_with_seq}"
  puts "mac: #{mac}"
  File.write('mac', mac)
  File.write('ip.sh', "arp -n | grep #{mac.gsub('-', ':')}")
  File.chmod(0755, 'ip.sh')

  return nil unless parse_response(url, hostname_with_seq, ipxe_script_path)

  job_hash, host_file_path = prepare_qemu(hostname_with_seq, mac, ipxe_script_path)

  run_qemu(job_hash, host_file_path, hostname_with_seq, mac)
end

def parse_ipxe_script(hostname, ipxe_script_path)
  append = ''
  initrds = ''
  kernel = ''
  File.foreach(ipxe_script_path) do |line|
    line_list = line.split
    case line_list[0]
    when '#'
      next
    when 'initrd'
      file = File.basename(line_list[1])
      if file == 'job.cgz'
        job_id = File.basename(File.dirname(line_list[1]))

        File.write('job_id', job_id.to_s)
      end
      system("wget --timestamping -nv -a #{LOG_FILE} #{line_list[1]}")
      initrds += "#{file} "
      puts initrds
    when 'kernel'
      kernel = File.basename(line_list[1])
      system("wget --timestamping -nv -a #{LOG_FILE} #{line_list[1]}")

      line_list = line_list.drop 2
      append = line_list.join(' ').gsub(/ initrd=[^ ]+/, '')
      puts append
    else
      next
    end
  end

  [append, initrds, kernel]
end

def custom_vm_info(hostname, ipxe_script_path)
  append, initrds, kernel = parse_ipxe_script(hostname, ipxe_script_path)

  `gzip -dc job.cgz | cpio -div`
  `grep -E "nr_|memory|minimum|group|RESULT_WEBDAV|result_root" lkp/scheduled/job.yaml | sed 's/^ *//' > lkp/scheduled/job_vm.yaml`

  create_yaml_variables("lkp/scheduled/job_vm.yaml")

  puts Dir.pwd
  job_yaml_vm_path = 'lkp/scheduled/job_vm.yaml'
  job_yaml_vm_path = 'lkp/scheduled/job_vm.yaml'

  return {} unless File.exist? job_yaml_vm_path

  job_hash = YAML.load_file job_yaml_vm_path

  job_hash['append'] = append
  job_hash['initrds'] = initrds
  job_hash['kernel'] = kernel

  job_hash
end

def prepare_qemu(hostname, mac, ipxe_script_path)
  LOGGER.info "prepare_qemu"

  retry_time = 0
  retry_remain_times = 600

  job_hash = custom_vm_info(hostname, ipxe_script_path)

  if job_hash['cpu_minimum'].nil? || job_hash['cpu_minimum'].empty?
    job_hash['cpu_minimum'] = job_hash['nr_cpu']
  end

  if job_hash['memory_minimum'].nil? || job_hash['memory_minimum'].empty?
    job_hash['memory_minimum'] = job_hash['memory']
  end

  host_file_path = "#{ENV['LKP_SRC']}/hosts/vm-#{job_hash['cpu_minimum'].to_i.to_s}p#{job_hash['memory_minimum'].to_i.to_s}g"

  return job_hash, host_file_path
end

def run_qemu(job_hash, host_file_path, hostname, mac)
  LOGGER.info "run_qemu"

  return unless File.exist? host_file_path
  #if hostname.match(/^(.*)-[0-9]+$/)
  #  tbox_group = Regexp.last_match(1)
  #else
  #  tbox_group = hostname
  #end
  #host = tbox_group.split('.')[0]
  #host_file = "#{ENV['LKP_SRC']}/hosts/#{host}"
  create_yaml_variables(host_file_path)

  host_hash = YAML.load_file host_file_path

  job_hash.merge! host_hash

  job_hash.each do |k, v|
    job_hash[k] = v.to_s if v.is_a? Integer
    job_hash[k] = v.join(' ') if v.is_a? Array
  end

  job_hash['mac'] = mac
  job_hash['hostname'] = hostname

  system(
    job_hash,
    "#{ENV['CCI_SRC']}/providers/#{ENV['provider']}/#{ENV['template']}.sh"
  )

  puts "pwd: #{Dir.pwd}, hostname: #{hostname}, mac: #{mac}"

  upload_dmesg(job_hash) if job_hash['id']
rescue StandardError => e
  puts e
  puts e.message
ensure
  LOGGER.info "finished the qemu"
end

def upload_dmesg(hash)
  if is_remote
    upload_url = "#{hash["RESULT_WEBDAV_HOST"]}:#{hash["RESULT_WEBDAV_PORT"]}#{hash["result_root"]}/dmesg"
  else
    upload_url = "http://#{hash["RESULT_WEBDAV_HOST"]}:#{hash["RESULT_WEBDAV_PORT"]}#{hash["result_root"]}/dmesg"
  end

  %x(curl -sSf -F "file=@#{LOG_FILE}" #{upload_url} --cookie "JOBID=#{hash["id"]}")
end

