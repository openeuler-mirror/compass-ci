# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'faye/websocket'
require 'eventmachine'

def reboot(type, job_id)
  r, io = IO.pipe
  if type == 'dc'
    res = system("docker rm -f #{job_id}", out: io, err: io)
  else
    res = system("pkill #{job_id}", out: io, err: io)
  end
  io.close

  msg = []
  r.each_line { |l| msg << l.chomp }
  return res, msg.join(';')
end

def report_event(info, res, msg)
  data = { 'msg' => msg, 'res' => res }
  data.merge!(info)
  data['state'] = 'reboot_testbox'
  cmd = "curl -H 'Content-Type: application/json' -X POST #{SCHED_HOST}:#{SCHED_PORT}/report_event -d '#{data.to_json}'"
  system cmd
end

def deal_reboot_msg(mq, msg, info, type)
  puts msg
  machine_info = JSON.parse(msg)
  job_id = machine_info['job_id']
  res, msg = reboot(type, job_id)
  report_event(machine_info, res, msg)
  mq.ack(info)
end

def get_memory_from_hostname(hostname)
  return hostname.split('.')[0][/[0-9]*g/][/[0-9]*/].to_i
end

def get_mem_available
  return %x(echo $(($(grep MemAvailable /proc/meminfo | awk '{print $2}') / 1024 / 1024))).to_i
end

def check_mem_available(hostname, memory)
  return (get_mem_available - memory) < 20 ? false : true
end

def get_mem_idle(mem_info_file)
  return %x(grep '^idle:' #{mem_info_file} | awk '{print $2}').to_i
end

def check_mem_idle(hostname, memory, mem_info_file)
  return get_mem_idle(mem_info_file) < memory ? false : true
end

def add_hostname_to_meminfo(hostname, memory, mem_info_file)
  if system("grep -q #{hostname}: #{mem_info_file}")
    puts "testbox was already added in meminfo: #{hostname}"
    return
  end

  mem_usage = %x(grep '^usage:' #{mem_info_file} | awk '{print $2}').to_i + memory
  mem_idle = %x(grep '^idle:' #{mem_info_file} | awk '{print $2}').to_i - memory

  cmd_update_usage = "sed -i 's/^usage: .*/usage: #{mem_usage} G/g' #{mem_info_file}"
  cmd_update_idle = "sed -i 's/^idle: .*/idle: #{mem_idle} G/g' #{mem_info_file}"
  cmd_add_testbox = "sed -i '$a#{hostname}: #{memory} G' #{mem_info_file}"

  system "#{cmd_update_usage} && #{cmd_update_idle} && #{cmd_add_testbox}"
end

def del_hostname_from_meminfo(hostname, memory, mem_info_file)
  if not system("grep -q #{hostname}: #{mem_info_file}")
    puts "testbox was already deleted in meminfo: #{hostname}"
    return
  end

  mem_usage = %x(grep '^usage:' #{mem_info_file} | awk '{print $2}').to_i - memory
  mem_idle = %x(grep '^idle:' #{mem_info_file} | awk '{print $2}').to_i + memory

  cmd_update_usage = "sed -i 's/^usage: .*/usage: #{mem_usage} G/g' #{mem_info_file}"
  cmd_update_idle = "sed -i 's/^idle: .*/idle: #{mem_idle} G/g' #{mem_info_file}"
  cmd_delete_testbox = "sed -i '/#{hostname}: #{memory} G/d' #{mem_info_file}"

  system "#{cmd_update_usage} && #{cmd_update_idle} && #{cmd_delete_testbox}"
end

def request_mem(hostname)
  mem_info_file = "/tmp/#{ENV['HOSTNAME']}/meminfo"
  request_success = false

  while not request_success
    begin
      memory = get_memory_from_hostname(hostname)
      f = get_lock("#{mem_info_file}.lock")

      if check_mem_available(hostname, memory) and check_mem_idle(hostname, memory, mem_info_file)
        # if all resources are sufficient, then record this testbox to resource file, and release the lock.
        add_hostname_to_meminfo(hostname, memory, mem_info_file)
        request_success = true
      end
    rescue Exception => e
      puts "request mem exception."
      puts e.message
      puts e.backtrace.inspect
    ensure
      f&.flock(File::LOCK_UN)
      f&.close

      # avoid all testboxes request lock at the same time
      if not request_success
        sleep(Random.rand(10))
      end
    end
  end
end

def release_mem(hostname)
  mem_info_file = "/tmp/#{ENV['HOSTNAME']}/meminfo"
  release_success = false

  while not release_success
    begin
      memory = get_memory_from_hostname(hostname)
      f = get_lock("#{mem_info_file}.lock")

      del_hostname_from_meminfo(hostname, memory, mem_info_file)
      release_success = true
    rescue Exception => e
      puts "release mem exception."
      puts e.message
      puts e.backtrace.inspect
    ensure
      f&.flock(File::LOCK_UN)
      f&.close
    end
  end
end

def save_running_suite
  return unless INDEX

  FileUtils.mkdir_p("/tmp/#{ENV['HOSTNAME']}") unless File.exist?("/tmp/#{ENV['HOSTNAME']}")
  f = File.new(SUITE_FILE, 'a')
  f.flock(File::LOCK_EX)
  f.puts("#{ENV['suite']}-#{INDEX}")
ensure
  f&.flock(File::LOCK_UN)
  f&.close
end

def manage_multi_qemu_docker(threads)
  loop do
    begin
      puts 'manage thread begin'
      monitor_mq_message(threads)
    rescue StandardError => e
      puts e.backtrace
      sleep 5
    end
  end
end

# msg:
# { "type" => "safe-stop" or "restart",
#   "hostname_array" => ["ALL"] or ["taishan200-2280-2s64p-256g--a1", "taishan200-2280-2s64p-256g--a2"]
#   "commit_id" => "xxxxxx"
# }
def monitor_mq_message(threads)
  mq = MQClient.new(MQ_HOST, MQ_PORT)
  queue = mq.fanout_queue('multi-manage', "#{HOSTNAME}-manage")
  queue.subscribe({ :block => true }) do |_info, _pro, msg|
    deal_mq_manage_message(threads, msg)
  end
end

def deal_mq_manage_message(threads, msg)
  puts msg
  msg = JSON.parse(msg)
  unless fit_me?(msg)
    puts 'This message is not for me'
    return
  end

  case msg['type']
  when 'safe-stop'
    manage_safe_stop(threads)
  when 'restart'
    manage_restart(threads, msg)
  else
    puts "deal mq manage message: unknow type message -- #{msg["type"]}"
  end
rescue StandardError => e
  puts e.backtrace.inspect
end

def fit_me?(msg)
  return true if msg['hostname_array'].include?('ALL')
  return true if msg['hostname_array'].include?(ENV['HOSTNAME'])

  return false
end

def manage_safe_stop(threads)
  File.new(SAFE_STOP_FILE, 'w')
  threads['manage'].exit
end

def manage_restart(threads, msg)
  update_code(msg['commit_id'])
  File.new(RESTART_FILE, 'w')
  threads.each do |name, thr|
    next if name == 'manage'

    puts "restart manage exit the thread: #{name}"
    thr.exit
  end
  threads['manage'].exit
end

def update_code(commit_id)
  # if there is no commit_id
  # the code is not updated
  return unless commit_id

  dir = "/tmp/#{ENV['HOSTNAME']}/restart"
  FileUtils.mkdir_p(dir) unless File.exist?(dir)

  f = File.new(RESTART_LOCK_FILE, 'a+')
  f.flock(File::LOCK_EX)
  return if f.readlines[0].to_s.chomp == commit_id

  update_restart_lock(commit_id)

  cmd = "cd #{ENV['CCI_SRC']};git pull;git reset --hard #{commit_id}"
  puts cmd
  system(cmd)
ensure
  f&.flock(File::LOCK_UN)
end

def update_restart_lock(commit_id)
  File.open(RESTART_LOCK_FILE, 'w') do |f|
    f.puts commit_id
  end
end

def safe_stop
  return unless INDEX
  return unless File.exist?(SAFE_STOP_FILE)

  running_suites = delete_running_suite

  # kill lkp-tests sleep process
  # so the multi-qemu job will over soon
  # only do this when there is no running multi-qemu in this testbox
  cmd = "kill -9 `ps -ef|grep sleep|grep #{ENV['runtime']}|grep -v grep|awk '{print $2}'`"
  if running_suites.empty?
    puts cmd
    system(cmd)
  end

  system("systemctl stop #{ENV['suite']}-#{INDEX}.service")
end

def get_lock(file)
  f = File.new(file, 'a')
  puts "#{file}: try to get file lock"
  f.flock(File::LOCK_EX)
  puts "#{file}: get file lock success"
  f
end

def delete_running_suite
  return [] unless INDEX

  f1 = File.new(SUITE_FILE)
  f1.flock(File::LOCK_EX)
  arr = []
  f1.each_line do |line|
    arr << line.chomp
  end
  arr.uniq!
  arr.delete("#{ENV['suite']}-#{INDEX}")

  f2 = File.new(SUITE_FILE, 'w')
  arr.each do |line|
    f2.puts line
  end
  return arr
ensure
  f2&.close
  f1&.flock(File::LOCK_UN)
  f1&.close
end

def ws_boot(url, hostname, uuid, ipxe_script_path = nil)
  threads = []
  response = nil

  EM.run do
    ws = Faye::WebSocket::Client.new(url)

    ws.on :open do |_event|
      puts "connect to #{url}"
    end

    ws.on :message do |event|
      response = deal_ws_event(event, threads, ws, hostname, uuid)
    end

    ws.on :close do
      threads.map(&:exit)
      EM.stop
    end
  end
  additional_ipxe_script(response, ipxe_script_path)
  response
rescue StandardError => e
  puts e
end

def additional_ipxe_script(response, ipxe_script_path)
  return unless response
  return unless ipxe_script_path

  File.open(ipxe_script_path, 'w') do |f|
    f.puts response
  end
end

def deal_ws_event(event, threads, ws, hostname, uuid)
  response = nil
  data = JSON.parse(event.data)
  case data['type']
  when 'request_memory', 'release_memory'
    thr = Thread.new do
      ack_memory(data['type'], ws, hostname, uuid)
    end
    threads << thr
  when 'boot'
    response = data['response']
  else
    raise 'unknow message type'
  end

  response
end

def ack_memory(type, ws, hostname, uuid)
  if uuid.to_s.empty?
    ws.send({ 'type' => type }.to_json)
    return
  end

  if type == 'request_memory'
    request_mem(hostname)
  else
    release_mem(hostname)
  end

  ws.send({ 'type' => type }.to_json)
end
