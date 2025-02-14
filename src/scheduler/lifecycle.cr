
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
    secs = job.timeout?
    return secs.to_i32 if secs
    if secs = job.runtime?
      secs = secs.to_i32
      secs += [secs // 8, 300].max + Math.sqrt(secs).to_i32
      return secs
    else
      return JOB_STAGE_TIMEOUT[stage]
    end
  when "renew"
    if job.hash_plain.has_key? "renew_seconds"
      secs = job.renew_seconds.to_i32
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
    @jobs_cache.each do |jobid, job|
      stage = job.job_stage
      next unless JOB_STAGE_TIMEOUT.has_key? stage
      timeout = get_timeout(job, stage)
      start_time = Time.parse(job["#{stage}_time"], "%Y-%m-%dT%H:%M:%S", Time.local.location)
      now = Time.local
      if now - start_time > Time::Span.new(seconds: timeout)
        if terminate_job(job) && JOB_STAGE_NAME2ID[stage] < JOB_STAGE_NAME2ID["finish"]
          job.job_stage = "incomplete"
          job.job_health = "timeout_#{stage}"
          on_job_updated(jobid)
        end
      end
    end
  end

end
