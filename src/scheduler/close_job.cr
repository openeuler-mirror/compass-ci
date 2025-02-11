# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched

  def update_wait_job_by_ss(job)
    job_waited = job.waited?
    return unless job_waited

    job_waited.not_nil!.each do |k, v|
      k_job = @es.get_job(k)
      next unless k_job
      next unless k_job.ss_wait_jobs?

      k_job.ss_wait_jobs.not_nil!.merge!({job.id => job.job_health})
      k_job.job_health = job.job_health if job.job_health != "success"
      @es.set_job(k_job)
    end
  end

  def on_job_finish(job)

    if job.job_health != "success"
      if job.has_key?("snapshot_id") && !job.snapshot_id.empty?
        data = {"build_id" => job.build_id, "job_id" => job.id, "build_type" => job.build_type, "emsx" => job.emsx}
        @etcd.put_not_exists("update_jobs/#{job.id}", data.to_json)
      end
    end

    if job.has_key?("running_time") && job.has_key?("finish_time")
      running_time = Time.parse(job.running_time, "%Y-%m-%dT%H:%M:%S", Time.local.location)
      finish_time = Time.parse(job.finish_time, "%Y-%m-%dT%H:%M:%S", Time.local.location)
      job.run_seconds = (finish_time - running_time).to_s
    end

    set_job2watch(job, "close", job.job_health)
    update_wait_job_by_ss(job)

    response = @es.set_job(job)
    if response["_id"] == nil
      # es update fail, raise exception
      raise "Error: es set job content fail!"
    end

    if job
      # need update the end job_health to etcd
      res = update_id2job(job)
      @log.info("scheduler update job to id2job #{job.id}: #{res}")
      res = @stats_worker.handle(job)
      @log.info("scheduler move in_process to extract_stats #{job.id}: #{res}")
    end

    report_workflow_job_event(job.id, job)
  end

end
