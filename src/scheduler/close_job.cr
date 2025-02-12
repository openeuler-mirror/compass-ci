# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched

  def on_job_close(job)

    if job.job_health != "success"
      if job.has_key?("snapshot_id") && !job.snapshot_id.empty?
        data = {"build_id" => job.build_id, "job_id" => job.id, "build_type" => job.build_type, "emsx" => job.emsx}
        @etcd.put_not_exists("update_jobs/#{job.id}", data.to_json)
      end
    end

    job.set_boot_seconds

    response = @es.set_job(job)
    if response["_id"] == nil
      # es update fail, raise exception
      raise "Error: es set job content fail!"
    end

    if job
      res = @stats_worker.handle(job)
      @log.info("scheduler move in_process to extract_stats #{job.id}: #{res}")
    end

    report_workflow_job_event(job.id, job)

    if job.job_stage == "incomplete"
      @jobs_cache.delete job.id64
      if @jobs_cache_in_submit.has_key? job.id64
        on_consumed_job(job)
      end
    end
  end

end
