require "./subqueue"
require "./constants"
require "./etcd_client"

class JobQuota
  def initialize
    @log = JSONLogger.new
    @etcd = EtcdClient.new
  end

  def total_jobs_quota(total_jobs_quota=TOTAL_JOBS_QUOTA)
    total_ready = @etcd.prefix_count("/queues/sched/ready/")
    if total_ready >= total_jobs_quota
      raise "The maximum number of jobs submitted has been reached."
    end
  end

  def subqueue_jobs_quota(job)
    sq_info = Subqueue.instance.get_subqueue_info(job.subqueue)
    soft_quota = sq_info["soft_quota"]
    hard_quota = sq_info["hard_quota"]

    soft_quota = soft_quota.as_i if soft_quota.is_a?(JSON::Any)
    hard_quota = hard_quota.as_i if hard_quota.is_a?(JSON::Any)

    sq_ready = @etcd.prefix_count("/queues/sched/ready/#{job.queue}/#{job.subqueue}")
    if sq_ready > soft_quota && sq_ready < hard_quota
      @log.warn({
        "message" => "The number of submitted jobs has reached the upper alarm limit, submitted: #{sq_ready}, limit: #{soft_quota}, subqueue: #{
job.subqueue}"
      })
    end

    if sq_ready >= hard_quota
      raise "The maximum number of jobs submitted has been reached, limit: #{hard_quota}, subqueue: #{job.subqueue}"
    end
  end
end
