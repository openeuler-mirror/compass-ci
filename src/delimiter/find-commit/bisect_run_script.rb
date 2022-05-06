#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

# frozen_string_literal: true

require 'json'
require_relative "#{ENV['CCI_SRC']}/src/delimiter/utils"

# git bisect run
class GitBisectRun
  def initialize(job_id, error_id, work_dir)
    @job_id = job_id
    @error_id = error_id
    @work_dir = work_dir
  end

  def git_bisect
    job = Utils.init_job_content(@job_id)
    commit = `git -C #{@work_dir} log --pretty=format:"%H" -1`
    job['upstream_commit'] = commit
    get_bisect_status job
  end

  private

  def get_bisect_status(job)
    status = Utils.get_job_status(job, @error_id)
    exit 125 unless status

    exit 1 if status.eql?('bad')

    exit 0
  rescue StandardError => e
    puts e.backtrace.inspect
    exit(-1)
  end
end

begin
  job_id = ARGV[0]
  error_id = ARGV[1]
  work_dir = ARGV[2]

  run = GitBisectRun.new job_id, error_id, work_dir
  run.git_bisect
rescue StandardError => e
  puts e.backtrace.inspect
  exit(-1)
end
