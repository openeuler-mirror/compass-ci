#!/usr/bin/env ruby

# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require_relative './basic_env'

if !ARGV.empty?
  puts 'Usage:'
  puts "input: #{__FILE__}"
  puts 'output: taskqueue_snap_yyyymmdd.md'
  puts '  #    id,   first add time, current queue'
  puts '  # 14703, 2020-07-22 14:33, sched/vm-2p8g--xxx/in_process'
  puts '  # 14831, 2020-07-22 17:51, sched/vm-2p8g--xxx/in_process'
  puts '  # crystal.89630, 2020-09-23 11:19, sched/vm-2p8g/in_process'
  puts '  # crystal.89667, 2020-09-23 11:20, sched/vm-2p8g/in_process'
  exit
end

# redis hash key "queues/id2content" is used by taskqueue
cmd = "#{CMD_BASE} queues/id2content , hgetall"
result = `#{cmd}`.chomp
results = result.split("\n")

task_info = []

# format time to "2020-09-29 14:23"
i = 0
task_num = results.size / 2
while i < task_num
  task_id = results[i]
  task_content = JSON.parse(results[i + 1])

  time = task_content['add_time']
  task_content['add_time'] = Time.at(time.to_f).strftime('%Y-%m-%d %H:%M') unless time.nil?

  time = task_content['move_time']
  task_content['move_time'] = Time.at(time.to_f).strftime('%Y-%m-%d %H:%M') unless time.nil?

  task_info << { 'id' => task_id, 'value' => task_content }

  i += 2
  set_progress(i, task_num)
end

# sort and put short information to file.
task_info.sort! { |a, b| a['value']['add_time'] <=> b['value']['add_time'] }
today = Time.now.strftime('%Y%m%d')
File.open("taskqueue_snap_#{today}.md", 'w') do |f|
  task_info.each do |task|
    f.write(task['id'] + ', ' + task['value']['add_time'] \
            + ', ' + task['value']['queue'] + "\n")
  end
end
