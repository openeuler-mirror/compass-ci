# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'set'
require 'json'
require 'fileutils'

require_relative './constants'
require_relative '../../lib/sched_client'
require_relative "#{ENV['LKP_SRC']}/lib/monitor"

# a utils module for delimiter service
module Utils
  class << self
    def clone_repo(repo, commit)
      repo_root = "#{TMEP_GIT_BASE}/#{File.basename(repo, '.git')}-#{`echo $$`}".chomp
      FileUtils.rm_r(repo_root) if Dir.exist?(repo_root)
      system("git clone -q #{repo} #{repo_root} && git -C #{repo_root} checkout -q #{commit}") ? repo_root : nil
    end

    def get_test_commits(work_dir, commit, day_agos)
      commits = Set.new
      day_agos.each do |day_ago|
        temp_commit = get_day_ago_commit(work_dir, commit, day_ago)
        commits << temp_commit if temp_commit
      end
      commits << get_last_commit(work_dir, commit) if commits.empty?
      return commits.to_a
    end

    def get_day_ago_commit(work_dir, commit, day_ago)
      date = `git -C #{work_dir} rev-list --first-parent --pretty=format:%cd \
      --date=short #{commit} -1 | sed -n 2p`.chomp!
      before = `date -d '-#{day_ago} day #{date}' +%Y-%m-%d`.chomp!
      day_ago_commit = `git -C #{work_dir} rev-list --before=#{before} \
      --pretty=format:%H --first-parent #{commit} -1 | sed -n 2p`.chomp!
      return day_ago_commit
    end

    def get_last_commit(work_dir, commit)
      last_commit = `git -C #{work_dir} rev-list --first-parent #{commit} -2 | sed -n 2p`.chomp!
      return last_commit
    end

    def parse_first_bad_commit(result)
      result = result.split(/\n/)
      result.each do |item|
        # b9e2a2fe56e92f4fe5ac15251ab3f77d645fbf82 is the first bad commit
        return item.split(/ /)[0] if item.end_with? 'is the first bad commit'
      end
    end

    def monitor_run_stop(query)
      monitor = Monitor.new("ws://#{MONITOR_HOST}:#{MONITOR_PORT}/filter")
      monitor.query = query
      monitor.action = { 'stop' => true }
      return monitor.run
    end

    def submit_job(job)
      sched = SchedClient.new
      response = sched.submit_job(job.to_json)
      puts "submit job response: #{response}"
      res_arr = JSON.parse(response)
      return nil if res_arr.empty? || !res_arr[0]['message'].empty?

      # just consider build-pkg job
      return res_arr[0]['job_id']
    end

    # submit the bad job
    # monitor the job id and job state query job stats when job state is extract_finished
    # according to the job stats return good/bad/nil
    def get_job_status(job, error_id)
      new_job_id = submit_job(job)
      puts "new job id: #{new_job_id}"
      return nil unless new_job_id

      query = { 'job_id': new_job_id, 'job_state': 'extract_finished' }
      extract_finished = monitor_run_stop(query)
      return nil unless extract_finished.zero?

      es = ESQuery.new
      new_job = es.query_by_id(new_job_id)
      return 'bad' if new_job['stats'].key?(error_id)

      return 'good'
    end

    def get_account_info
      ESQuery.new(index: 'accounts').query_by_id(DELIMITER_ACCONUT)
    end

    def init_job_content(job_id)
      es = ESQuery.new
      job = es.query_by_id(job_id)
      raise "es query job id: #{job_id} failed!" unless job

      account_info = get_account_info
      raise "query #{DELIMITER_ACCONUT} account info failed!" unless account_info

      job['suite'] = 'bisect'
      job['my_uuid'] = account_info['my_uuid']
      job['my_name'] = account_info['my_name']
      job['my_email'] = account_info['my_email']
      job['bad_job_id'] = job_id

      job.delete('error_ids')
      job.delete('start_time')
      job.delete('end_time')
      job.delete('loadavg')

      return job
    end

    def parse_bisect_log(git_dir)
      bisect_log = %x(git -C #{git_dir} bisect log)
      bisect_log_arr = bisect_log.split(/\n/)
      bisect_log_arr.keep_if { |item| item.start_with?('#') }

      return bisect_log_arr
    end

    def create_bisect_log(git_dir)
      log_file = File.join(TMP_RESULT_ROOT, "bisect.log")
      log_content = parse_bisect_log(git_dir)
      File.open(log_file, 'w') do |f|
        log_content.each { |line| f.puts(line) }
      end
    end
  end
end
