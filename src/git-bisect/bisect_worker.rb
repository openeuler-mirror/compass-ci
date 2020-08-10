# frozen_string_literal: true

require_relative '../../lib/es_query'
require_relative '../../lib/taskqueue_client'
require_relative '../../lib/sched_client'

require_relative './bisect_utils'

# git bisect worker
class BisectWorker
  def initialize
    @es = ESQuery.new
    @tq = TaskQueueClient.new
    @sched = SchedClient.new
  end

  # consume bisect queue and start bisect
  def consume_bisect
    response = @tq.consume_task(BISECT_TASK_QUEUE)
    return unless response.code == 200

    body = JSON.parse(response.body).to_hash
    @error_id = body['error_id']
    @bad_job_id = body['job_id']
    puts "consume task response body: #{body}"
    return unless set_upstream

    start_bisect
  end

  private

  def set_upstream
    @bad_job = @es.query_by_id @bad_job_id
    return false unless @bad_job

    @bad_job.delete('stats')
    @bad_job['tbox_group'] = BISECT_TBOX_GROUP
    @upstream_repo = @bad_job['upstream_repo']
    @upstream_commit = @bad_job['upstream_commit']
    puts "upstream repo: #{@upstream_repo}"
    puts "upstream commit: #{@upstream_commit}"
    return false unless @upstream_repo
    return false unless @upstream_commit

    return true
  end

  # start bisect
  # clone upstream repo
  # find the good commit
  # run git bisect start use upstream_commit and good_commit
  # run bisect script get the bisect info
  def start_bisect
    @work_dir = BisectUtils.clone_repo(@upstream_repo)
    puts "work_dir = #{@work_dir}"
    return unless @work_dir

    good_commit = find_good_commit
    puts "good commit: #{good_commit}"
    return unless good_commit

    return unless system("git -C #{@work_dir} bisect start #{@upstream_commit} #{good_commit}")

    bisect_info = `git -C #{@work_dir} bisect run #{BISECT_RUN_SCRIPT} #{@bad_job_id} #{@error_id}\
    #{BISECT_TBOX_GROUP} #{@work_dir}`
    puts bisect_info
    FileUtils.rm_r(@work_dir) if Dir.exist?(@work_dir)
  end

  # find good commit
  # get a commit offset upstream commit 1, 3, 10, 30 day ago
  # submit a job and return the commit status good/bad/nil
  # return the offset commit if the commit status is good
  def find_good_commit
    [1, 3, 10, 30].each do |day_ago|
      day_ago_commit = BisectUtils.get_day_ago_commit(@upstream_commit, day_ago, @work_dir)
      next unless day_ago_commit
      next if day_ago_commit == @upstream_commit

      commit_status = get_commit_status(day_ago_commit)
      next unless commit_status
      return day_ago_commit if commit_status == 'good'
    end
    return nil
  end

  # get commit status
  # submit the bad job
  # cycle 10 times to check the job stats, everytime interval 60s
  # according to the job stats return good/bad/nil
  def get_commit_status(commit)
    @bad_job['upstream_commit'] = commit
    new_job_id = @sched.submit_job @bad_job.to_json
    puts new_job_id
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
