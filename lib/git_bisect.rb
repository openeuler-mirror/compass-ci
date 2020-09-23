# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require_relative 'es_query'
require_relative 'sched_client'
require_relative "../src/delimiter/utils"
require_relative "#{ENV['LKP_SRC']}/lib/monitor"

# find the first bad commit
class GitBisect
  def initialize(task)
    @es = ESQuery.new
    @task = task
  end

  def find_first_bad_commit
    # set object property
    set_ids
    set_bad_job
    set_upstream
    set_work_dir
    set_good_commit

    start_bisect
  end

  private

  def set_ids
    puts "task content: #{@task}"
    @error_id = @task['error_id']
    @bad_job_id = @task['job_id']
  end

  def set_bad_job
    @bad_job = @es.query_by_id @bad_job_id
    raise "es query job id: #{@bad_job_id} failed!" unless @bad_job

    @bad_job.delete('uuid')
    @bad_job.delete('stats')
    @bad_job.delete('id')
    @bad_job.delete('error_ids')
    @bad_job['tbox_group'] = DELIMITER_TBOX_GROUP
  end

  def set_upstream
    @upstream_repo = @bad_job['upstream_repo']
    @upstream_commit = @bad_job['upstream_commit']
    puts "upstream_repo: #{@upstream_repo}"
    puts "upstream_commit: #{@upstream_commit}"
    raise 'upstream info is null' unless @upstream_repo || @upstream_commit

    @upstream_repo_git = "git://#{GIT_MIRROR_HOST}/#{@upstream_repo}"
  end

  def set_work_dir
    @work_dir = Utils.clone_repo(@upstream_repo_git, @upstream_commit)
    puts "work_dir: #{@work_dir}"
    raise "checkout repo: #{@upstream_repo} to commit: #{@upstream_commit} failed!" unless @work_dir
  end

  def set_good_commit
    @good_commit = find_good_commit
    raise 'can not find a good commit' unless @good_commit
  end

  # run git bisect start use upstream_commit and good_commit
  # run bisect script get the bisect info
  def start_bisect
    puts "bad_commit: #{@upstream_commit}"
    puts "good_commit: #{@good_commit}"

    result = `git -C #{@work_dir} bisect start #{@upstream_commit} #{@good_commit}`
    temp = result.split(/\n/)
    if temp[0].include? 'Bisecting'
      result = `git -C #{@work_dir} bisect run #{BISECT_RUN_SCRIPT} #{@bad_job_id} "#{@error_id}" \
      "#{DELIMITER_TBOX_GROUP}" #{@work_dir}`
    end
    FileUtils.rm_r(@work_dir) if Dir.exist?(@work_dir)
    puts "\nbisect result: #{result}"
    analyse_result(result)
  end

  def analyse_result(result)
    temp = result.split(/\n/)
    return nil unless temp[0].include?('is the first bad commit') || temp[-1].include?('bisect run success')

    first_bad_commit = Utils.parse_first_bad_commit(result)

    return Hash['repo' => @upstream_repo, 'commit' => first_bad_commit,
                'job_id' => @bad_job_id, 'error_id' => @error_id]
  end

  # first search the good commit in db
  # second search the good commit by job
  def find_good_commit
    good_commit = find_good_commit_by_db
    return good_commit if good_commit

    good_commit = find_good_commit_by_job
    return good_commit if good_commit
  end

  def find_good_commit_by_db
    # todo
    return nil
  end

  # get a commit array offset upstream commit
  # return the offset commit if the commit status is good or return nil
  def find_good_commit_by_job
    day_agos = [1, 3, 10, 30]
    commits = Utils.get_test_commits(@work_dir, @upstream_commit, day_agos)
    puts "commits: #{commits}"
    commits.each do |commit|
      commit_status = get_commit_status_by_job(commit)
      next unless commit_status
      return commit if commit_status == 'good'
    end

    return nil
  end

  # get commit status by submit the bad job
  # according to the job stats return good/bad/nil
  def get_commit_status_by_job(commit)
    @bad_job['upstream_commit'] = commit
    return Utils.get_job_status(@bad_job, @error_id)
  end
end
