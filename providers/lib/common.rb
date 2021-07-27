# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'fileutils'

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

def total_allocated_mem
  qemus_allocated_mem = %x{echo "$(ps -ef | grep qemu | grep result)" | awk -F "-m " '{print $2}' | awk -F "G" '{print $1}' | awk '{sum += $1};END {print sum}'}.to_i
  dockers_allocated_mem = %x{echo "$(ps -ef | grep docker | grep result)" | awk -F "-m " '{print $2}' | awk -F "g" '{print $1}' | awk '{sum += $1};END {print sum}'}.to_i
  qemus_allocated_mem + dockers_allocated_mem
end

def max_allocable_memory
  (%x{cat /proc/meminfo | awk '/MemTotal/ {print $2}'}.to_i * 8 /10) >> 20
end

def check_mem_quota
  while total_allocated_mem > max_allocable_memory
    puts "Total Allocated Memory is bigger than Max Allocable memory: #{total_allocated_mem}G > #{max_allocable_memory}G, wait for memory release!"
    sleep(30)
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
    puts 'deal mq manage message: unknow type message'
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
  arr.delete("#{HOSTNAME}-#{INDEX}")

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
