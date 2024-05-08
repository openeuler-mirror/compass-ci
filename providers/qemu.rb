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
require_relative '../lib/mq_client'
require_relative '../container/defconfig'

os_arch = %x(arch).chomp
hostname = ENV.fetch('hostname', 'vm-1p1g-1')
queues = ENV.fetch('queues', "vm-1p1g.#{os_arch}")

names = Set.new %w[
  SCHED_HOST
  SCHED_PORT
  MQ_HOST
  MQ_PORT
  DOMAIN_NAME
]

defaults = relevant_defaults(names)
SCHED_HOST = defaults['SCHED_HOST'] || '172.17.0.1'
SCHED_PORT = defaults['SCHED_PORT'] || 3000

MQ_HOST = defaults['MQ_HOST'] || ENV['MQ_HOST'] || ENV['LKP_SERVER'] || 'localhost'
MQ_PORT = defaults['MQ_PORT'] || ENV['MQ_PORT'] || 5672
DOMAIN_NAME = defaults['DOMAIN_NAME']

WORKSPACE = '/srv/vm'
LOG_FILE = '/srv/cci/serial/logs/' + hostname
LOGGER = Logger.new(LOG_FILE)

def get_url(hostname, left_mem, mac)
  if ENV['is_remote'] == 'true'
    "ws://#{DOMAIN_NAME}/ws/boot.ipxe?mac=#{mac}&hostname=#{hostname}&left_mem=#{left_mem}&tbox_type=vm&is_remote=true"
  else
    "ws://#{SCHED_HOST}:#{SCHED_PORT}/ws/boot.ipxe?mac=#{mac}&hostname=#{hostname}&left_mem=#{left_mem}&tbox_type=vm&is_remote=false"
  end
end

def register_host2redis(mem_total)
  hostname = ENV.fetch('hostname')
  is_remote = ENV.fetch('is_remote').to_s
  arch = get_arch

  if is_remote == 'true'
    config = load_my_config
    owner = config['ACCOUNT']
    jwt = load_jwt?
    api_client = RemoteClient.new()
    url = "https://#{DOMAIN_NAME}/api/register-host2redis?hostname=#{hostname}&type=vm&owner=#{owner}&max_mem=#{mem_total}&is_remote=#{is_remote}&arch=#{arch}"
    response = api_client.register_host2redis(url, jwt)
    return if response.nil? || response.empty?
    response = JSON.parse(response)
    if response.has_key?('status_code') and response['status_code'] == 401
      puts "jwt maybe timeout retry once"
      jwt = load_jwt?(force_update=true) # jwt maybe timeout and retry once
      api_client = RemoteClient.new(SCHED_HOST, SCHED_PORT)
      response = api_client.register_host2redis(url, jwt)
      return if response.nil? || response.empty?
      response = JSON.parse(response)
    end
    check_return_code(response)
    puts JSON.pretty_generate(response)
  else
    cmd = "curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/register-host2redis?hostname=#{hostname}&type=vm&owner=local&max_mem=#{mem_total}&is_remote=#{is_remote}&arch=#{arch}'"
    system cmd
  end
end

def del_host2queues(hostname, is_remote)
  hostname = ENV.fetch('hostname')
  is_remote = ENV.fetch('is_remote').to_s

  if is_remote == 'true'
    jwt = load_jwt?
    config = load_my_config
    api_client = RemoteClient.new()
    url = "https://#{DOMAIN_NAME}/api/del_host2queues?hostname=#{hostname}"
    response = api_client.del_host2queues(url, jwt)
    return if response.nil? || response.empty?
    response = JSON.parse(response)
    if response.has_key?('status_code') and response['status_code'] == 401
      jwt = load_jwt?(force_update=true) # jwt maybe timeout and retry once
      api_client = RemoteClient.new(SCHED_HOST, SCHED_PORT)
      response = api_client.del_host2queues(url, jwt)
      return if response.nil? || response.empty?
      response = JSON.parse(response)
    end
    check_return_code(response)
    puts JSON.pretty_generate(response)
  else
    cmd = "curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/del_host2queues?host=#{hostname}'"
    system cmd
  end
end

def heart_beat
  hostname = ENV.fetch('hostname')
  is_remote = ENV.fetch('is_remote').to_s

  jwt = nil
  if is_remote == 'true'
    jwt = load_jwt?
    url = "https://#{DOMAIN_NAME}/api/heart-beat?hostname=#{hostname}&type=vm&is_remote=#{is_remote}"
  else
    url = "http://#{SCHED_HOST}:#{SCHED_PORT}/heart-beat?hostname=#{hostname}&type=vm&is_remote=#{is_remote}"
  end

  api_client = RemoteClient.new()
  response = api_client.heart_beat(url, jwt)
  response = JSON.parse(response)
  puts "heart_beat runing status: #{response}"
  if response.has_key?('status_code') and response['status_code'] == 1001
    mem_total = get_total_memory
    register_host2redis(mem_total)
  end
end

def parse_response(url, hostname, ipxe_script_path, is_remote)
  puts "multi-qemu in running..."

  index = ENV.fetch('index', nil)

  LOGGER.info "Starting qemu for #{hostname}"
  LOGGER.info "Ws boot start"

  begin
    response = ws_boot(url, hostname, index, ipxe_script_path, is_remote)

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

def set_host_info(hostname, mac)
  # use "," replace " "
  api_queues = ENV['queues'].gsub(/ +/, ',')

  system("curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/set_host_mac?hostname=#{hostname}&mac=#{mac}'")
  system("curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/set_host2queues?host=#{hostname}&queues=#{api_queues}'")
end

def del_host_info(hostname, mac)
  system("curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/del_host_mac?mac=#{mac}' > /dev/null 2>&1")
  system("curl -X PUT 'http://#{SCHED_HOST}:#{SCHED_PORT}/del_host2queues?host=#{hostname}' > /dev/null 2>&1")
end

def post_work(hostname, mac, lockfile)
  del_host_info(hostname, mac)
  release_mem(hostname) if ENV['index']
  system("lockfile-remove --lock-name #{lockfile}")
end

def get_lock(retry_time, retry_remain_times, lockfile)
  puts "try to get lock: #{lockfile}"

  system("lockfile-create -q --lock-name -p --retry 0 #{lockfile}")

  puts "vm got lock successed: #{lockfile}, uuid: #{ENV['UUID']}"
  return true
rescue
  puts 'rescue get lock'
  retry_time += 1

  if retry_time <= retry_remain_times
    puts "retry times: #{retry_time}"

    retry
  else
    return false
  end
end

def check_host_status(free_mem)
  rest_vms = pre_check_tbox('vm')
  if rest_vms
    return rest_vms
  else
    puts "testbox is not reday"
    return nil
  end
end

def main
  hostname = ENV['hostname']
  is_remote = ENV['is_remote']

  free_mem = get_free_memory
  return nil if free_mem < 4

  host_vms = check_host_status(free_mem)
  return nil if host_vms.nil? || host_vms.empty?

  host_seq = host_vms[-1].to_s
  hostname_with_seq = "#{hostname}-#{host_seq}"

  Dir.mkdir("#{WORKSPACE}/#{hostname_with_seq}") unless Dir.exists? "#{WORKSPACE}/#{hostname_with_seq}"
  Dir.chdir("#{WORKSPACE}/#{hostname_with_seq}")
  ipxe_script_path="#{WORKSPACE}/#{hostname_with_seq}/ipxe_script"

  left_mem = get_free_memory
  mac = `echo #{hostname_with_seq} | md5sum`.chomp.gsub(/^(\w\w)(\w\w)(\w\w)(\w\w)(\w\w).*/, '0a-\1-\2-\3-\4-\5')

  puts "hostname: #{hostname_with_seq}"
  puts "mac: #{mac}"
  File.write('mac', mac)
  File.write('ip.sh', "arp -n | grep #{mac.gsub('-', ':')}")
  File.chmod(0755, 'ip.sh')

  url = get_url(hostname_with_seq, left_mem, mac)

  return nil unless parse_response(url, hostname_with_seq, ipxe_script_path, is_remote)

  thr = Thread.new do
    run_qemu(hostname_with_seq, host_seq, thr, mac, ipxe_script_path, is_remote)
  end
end

def parse_ipxe_script(hostname, ipxe_script_path)
  log_file = "/srv/cci/serial/logs/#{hostname}"
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
      system("wget --timestamping -nv -a #{log_file} #{line_list[1]}")
      initrds += "#{file} "
      puts initrds
    when 'kernel'
      kernel = File.basename(line_list[1])
      system("wget --timestamping -nv -a #{log_file} #{line_list[1]}")

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
  `grep -E "nr_|memory|minimum|group|RESULT_WEBDAV" lkp/scheduled/job.yaml > lkp/scheduled/job_vm.yaml`

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

def run_qemu(hostname, host_seq, thr, mac, ipxe_script_path, is_remote)
  puts "run_qemu"
  load_path = "#{WORKSPACE}/#{hostname}"
  FileUtils.mkdir_p(load_path) unless File.exist?(load_path)

  lockfile = "#{load_path}/#{hostname}.lock"

  retry_time = 0
  retry_remain_times = 600

  get_lock(retry_time, retry_remain_times, lockfile)

  set_host_info(hostname, mac)
  at_exit { post_work(hostname, mac, lockfile) }

  job_hash = custom_vm_info(hostname, ipxe_script_path)

  if job_hash['cpu_minimum'].nil? || job_hash['cpu_minimum'].empty?
    job_hash['cpu_minimum'] = job_hash['nr_cpu']
  end

  if job_hash['memory_minimum'].nil? || job_hash['memory_minimum'].empty?
    job_hash['memory_minimum'] = job_hash['memory']
  end

  record_spec_mem(job_hash, host_seq, 'vm')

  host_file_path = "#{ENV['LKP_SRC']}/hosts/vm-#{job_hash['cpu_minimum'].to_i.to_s}p#{job_hash['memory_minimum'].to_i.to_s}g"
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
  puts "vm finish run, release lock: #{lockfile}, uuid: #{ENV['UUID']}"

  upload_dmesg(job_hash, is_remote) if job_hash['id']
rescue StandardError => e
  puts e
  puts e.message
ensure
  LOGGER.info "finished the qemu"
  release_spec_mem(hostname, job_hash, 'vm')
  clean_test_source(hostname)
  thr.exit
end

def upload_dmesg(hash, is_remote)
  log_file = "/srv/cci/serial/logs/#{hash['hostname']}"

  if is_remote == 'true'
    upload_url = "#{hash["RESULT_WEBDAV_HOST"]}:#{hash["RESULT_WEBDAV_PORT"]}#{hash["result_root"]}/dmesg"
  else
    upload_url = "http://#{hash["RESULT_WEBDAV_HOST"]}:#{hash["RESULT_WEBDAV_PORT"]}#{hash["result_root"]}/dmesg"
  end

  %x(curl -sSf -T "#{log_file}" #{upload_url} --cookie "JOBID=#{hash["id"]}")
end

def loop_heart_beat(heart_thr, safe_stop_file)
  hostname = ENV.fetch('hostname')
  is_remote = ENV.fetch('is_remote').to_s

  loop do
    begin
      heart_thr.exit if File.exist?(safe_stop_file)
      heart_beat
      # puts "heart_beat is running"
    rescue StandardError => e
      puts e.backtrace
      sleep 10
    ensure
      sleep 30
    end
  end
end

def start
  safe_stop_file = "/tmp/#{ENV['HOSTNAME']}/safe-stop"

  mem_total = get_total_memory
  register_host2redis(mem_total)
  heart_thr = Thread.new do
    loop_heart_beat(heart_thr, safe_stop_file)
  end

  loop do
    begin
      break if File.exist?(safe_stop_file)
      main

    rescue StandardError => e
      puts e.backtrace
      puts e
      sleep 25
    ensure
      sleep 5
    end
  end
  del_host2queues
end

start
