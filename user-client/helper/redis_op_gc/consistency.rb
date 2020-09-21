#!/usr/bin/env ruby

# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'optparse'
require_relative './garbage_collection'

options = { 'output' => false, 'remove' => false, 'days' => 3 }

optparse = OptionParser.new do |opts|
  opts.banner = 'Usage: consistency [options]'

  help = "check alive more than number days, default is #{options['days']}"
  opts.on('-dN', '--days=number', Integer, help) do |n|
    options['days'] = n
  end

  help = "output abnormal task to man_del.id and too_long.id, default is #{options['output']}"
  opts.on('-o', false, help) do
    options['output'] = true
  end

  opts.on('-r', false,
          "remove not exists task, default is #{options['remove']}") do
    options['remove'] = true
  end
end

optparse.parse!
puts "options: #{options.inspect}"

# redis hash key "queues/id2content" is used by taskqueue
#   it records all "task id" and task's current redis key value
# like:
#   25536
#   {"add_time":1596876735.944146, "queue":"sched/vm-hi1620-2p8g--$USER/ready"}
cmd = "#{CMD_BASE} queues/id2content , hgetall"
result = `#{cmd}`.chomp
results = result.split("\n")

normal = 0
manual_deleted = []
alive_too_long = []

# use AbnormalIdDetect to check the task:
#      [MANUAL_DELETED, ALIVE_TOO_LOONG, else]
# if set remove option
#   then use GarbagCollection to remove not exists task
#   no define process to alive too long task now
i = 0
task_num = results.size / 2
while i < task_num
  task_id = results[i]
  task_content = results[i + 1]
  abn = AbnormalIdDetect.new(task_id, options['days'], task_content)
  status = abn.check

  case status.gsub(/=.*/, '')
  when MANUAL_DELETED
    manual_deleted << task_id
    if options['remove']
      gc = GarbageCollection.new(task_id, options['days'], task_content)
      gc.run
    end
  when ALIVE_TOO_LONG
    alive_too_long << task_id
  else
    normal += 1
  end

  i += 2
  set_progress(i, task_num)
end

# print task statistics information
puts ''
puts "Total #{task_num} task"
puts "    - #{manual_deleted.size} manual deleted"
puts "    - #{alive_too_long.size} alive more than #{options['days']} days"
puts "    - #{normal} others"

# output task id to file
#             man_del.id for manual deleted task
#            too_long.id for alive too long task
if options['output']
  File.open('man_del.id', 'w') do |f|
    f.write(manual_deleted.join("\n"))
  end

  File.open('too_long.id', 'w') do |f|
    f.write(alive_too_long.join("\n"))
  end
end
