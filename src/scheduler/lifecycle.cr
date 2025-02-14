
# default timeout for each stage
# unit: seconds
JOB_STAGE_TIMEOUT = {
  "download"     =>  3600,
  "boot"         =>  1200,
  "setup"        =>   600,
  "running"      =>  3600,
  "wait_peer"    =>  7200,
  "uploading"    =>  3600,
  "post_run"     =>  1800,
  "finish"       =>  300,
  "manual_check" =>  10 * 3600,     # 10 hours
  "renew"        =>  3 * 24 * 3600, # 3 days
}

def get_timeout(job, stage) : Int32
  case stage
  when "boot"
    case job.tbox_type
    when "dc"
      180
    when "vm"
      JOB_STAGE_TIMEOUT[stage] // 2
    else
      JOB_STAGE_TIMEOUT[stage]
    end
  when "running"
    secs = job.timeout_seconds
  when "renew"
    if job.hash_int32.has_key? "renew_seconds"
      secs = job.renew_seconds
      return secs
    else
      JOB_STAGE_TIMEOUT[stage]
    end
  else
      JOB_STAGE_TIMEOUT[stage]
  end
end

class Sched

  def start_lifecycle_worker
    spawn {
      loop do
        terminate_timeout_jobs
        sleep 1.minute
      end
    }
  end

  def terminate_timeout_jobs
    now = Time.utc
    @jobs_cache.each do |jobid, job|
      next if job.deadline_utc > now

      stage = job.job_stage
      next unless JOB_STAGE_TIMEOUT.has_key? stage

      timeout = get_timeout(job, stage)
      start_time = Time.parse(job["#{stage}_time"], "%Y-%m-%dT%H:%M:%S", Time.local.location)

      job.deadline_utc = start_time.to_utc + timeout
      if job.deadline_utc < now
        if terminate_job(job) && JOB_STAGE_NAME2ID[stage] < JOB_STAGE_NAME2ID["finish"]
          job.job_stage = "incomplete"
          job.job_health = "timeout_#{stage}"
          on_job_updated(jobid)
        end
      end
    end
  end

end
