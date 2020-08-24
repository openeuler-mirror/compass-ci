# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'json'
require_relative '../../../lib/es_query'
require_relative '../../../lib/sched_client'

require_relative '../utils'

# find the first bad commit
class GitBisect
  def initialize(task)
    @es = ESQuery.new
    @sched = SchedClient.new
    @task = task
  end

  def find_first_bad_commit
    # set object property
    set_ids
    set_bad_job
    set_upstream
    set_work_dir
    set_good_commit

    bisect_result = start_bisect
    return bisect_result
  end

  private

  def set_ids
    puts "task content: #{@task}"
    @error_id = @task['error_id']
    @bad_job_id = @task['job_id']
  end

  def set_bad_job
    @bad_job = @es.query_by_id @bad_job_id
    @bad_job.delete('stats')
    @bad_job.delete('id')
    @bad_job['tbox_group'] = DELIMITER_TBOX_GROUP
  end

  def set_upstream
    @upstream_repo = @bad_job['upstream_repo']
    @upstream_commit = @bad_job['upstream_commit']
    puts "upstream_repo: #{@upstream_repo}"
    puts "upstream_commit: #{@upstream_commit}"
    raise 'upstream repo is null' unless @upstream_repo || @upstream_commit
  end

  def set_work_dir
    @work_dir = Utils.clone_repo(@upstream_repo, @upstream_commit)
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
    return result
  end

  # first search the good commit in db
  # second search the good commit by job
  def find_good_commit
    good_commit = find_good_commit_by_db
    return good_commit if good_commit

    good_commit = find_good_commit_by_job
    return good_commit if good_commit

    return
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

  # get commit status
  # submit the bad job
  # cycle 10 times to check the job stats, everytime interval 60s
  # according to the job stats return good/bad/nil
  def get_commit_status_by_job(commit)
    @bad_job['upstream_commit'] = commit
    new_job_id = @sched.submit_job @bad_job.to_json
    puts "new_job_id: #{new_job_id}"
    10.times do
      sleep 60

      new_job = @es.query_by_id new_job_id

      next unless new_job
      next unless new_job['stats']
      return 'bad' if new_job['stats'].key?(@error_id)

      return 'good'
    end
    return nil
  end
end
