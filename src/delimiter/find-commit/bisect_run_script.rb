#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+

# frozen_string_literal: true

require 'json'
require_relative "#{ENV['CCI_SRC']}/lib/es_query"
require_relative "#{ENV['CCI_SRC']}/src/delimiter/utils"

# git bisect run
class GitBisectRun
  def initialize(job_id, error_id, tbox_group, work_dir)
    @es = ESQuery.new
    @job_id = job_id
    @error_id = error_id
    @tbox_group = tbox_group
    @work_dir = work_dir
  end

  def git_bisect
    job = @es.query_by_id @job_id
    job.delete('stats') if job.key?('stats')
    job['tbox_group'] = @tbox_group
    commit = `git -C #{@work_dir} log --pretty=format:"%H" -1`
    job['upstream_commit'] = commit
    get_bisect_status job
  end

  private

  def get_bisect_status(job)
    new_job_id = Utils.submit_job(job)
    exit 125 unless new_job_id

    query = { 'job_id': new_job_id, 'job_state': 'extract_finished' }
    extract_finished = Utils.monitor_run_stop(query)
    exit 125 unless extract_finished.zero?

    new_job = @es.query_by_id new_job_id
    exit 1 if new_job['stats'].key?(@error_id)

    exit 0
  end
end

job_id = ARGV[0]
error_id = ARGV[1]
tbox_group = ARGV[2]
work_dir = ARGV[3]

run = GitBisectRun.new job_id, error_id, tbox_group, work_dir
run.git_bisect
