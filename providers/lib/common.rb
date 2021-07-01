# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

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

def total_allocated_mem
  qemus_allocated_mem = %x{echo "$(ps -ef | grep qemu | grep result)" | awk -F "-m " '{print $2}' |
awk -F "G" '{print $1}' | awk '{sum += $1};END {print sum}'}.to_i
  dockers_allocated_mem = %x{echo "$(ps -ef | grep docker | grep result)" | awk -F "-m " '{print $2}
' | awk -F "g" '{print $1}' | awk '{sum += $1};END {print sum}'}.to_i
  qemus_allocated_mem + dockers_allocated_mem
end

def max_allocable_memory
  (%x{cat /proc/meminfo | awk '/MemTotal/ {print $2}'}.to_i * 8 /10) >> 20
end

def check_mem_quota
  while total_allocated_mem > max_allocable_memory
    puts "Total Allocated Memory is bigger than Max Allocable memory: #{total_allocated_mem}G > #{ma
x_allocable_memory}G, wait for memory release!"
    sleep(30)
  end
end
