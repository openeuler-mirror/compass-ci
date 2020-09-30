#!/usr/bin/env ruby

# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './force_delete'

if ARGV.empty? || ARGV.include?("-h") || ARGV.include?("--help")
  puts "Usage: #{__FILE__} task_id[|task_ids]"
  puts '       delete special task with [task_id]'
  puts '    or delete special task from [task_ids] file'
  puts "\n--- example ---"
  puts " input: #{__FILE__} z9.11734 nolab.11342"
  puts 'output: <none>'
  puts '  # delete (z9.11734 nolab.11342) at taskqueue and scheduler'
  exit
end

task_ids = []
ARGV.each do |id|
  task_ids += IO.readlines(id) if File.exist?(id)
  task_ids << id unless File.exist?(id)
end

i = 0
task_num = task_ids.size
while i < task_num
  task_id = task_ids[i]
  fd = ForceDelete.new(task_id)
  fd.run

  i += 1
  set_progress(i, task_num)
end
