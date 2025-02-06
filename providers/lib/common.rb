# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'fileutils'
require 'faye/websocket'
require 'eventmachine'

require_relative 'jwt'

def reboot(type, job_id)
  r, io = IO.pipe
  res = if type == 'dc'
          system("docker rm -f #{job_id}", out: io, err: io)
        else
          system("pkill #{job_id}", out: io, err: io)
        end
  io.close

  msg = []
  r.each_line { |l| msg << l.chomp }
  return res, msg.join(';')
end

def get_total_memory
  return %x(grep MemTotal /proc/meminfo | awk '{print $2}').to_i / 1024
end

def get_free_memory
  return %x(grep MemFree /proc/meminfo | awk '{print $2}').to_i / 1024
end

def get_arch
  return %x(arch).chomp
end

def deal_manage_message(threads, msg)
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
    puts "deal manage message: unknow type message -- #{msg['type']}"
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
  threads['manage'].exit
end

def manage_restart(threads, msg)
  update_code(msg['commit_id'])
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

  dir = "#{ENV['CCI_SRC']}/in-pull"
  return unless File.exist? dir
  FileUtils.mkdir(dir) rescue return

  cmd = "cd #{ENV['CCI_SRC']};git pull;git reset --hard #{commit_id}"
  puts cmd
  system(cmd)
ensure
  FileUtils.rmdir(dir)
end

def safe_stop
  # TODO: stop docker / qemu started by us

  system("systemctl stop #{ENV['suite']}.service")
end
