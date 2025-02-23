# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched

  # Cancel a job by ID
  def api_cancel_job(job_id : Int64) : Tuple(HTTP::Status, String)
    job = get_job(job_id)
    return {HTTP::Status::NOT_FOUND, "Job not found"} unless job

    # Validate the job's stage
    unless job.istage == 0
      return {HTTP::Status::FORBIDDEN, "Job already running"}
    end

    change_job_stage(job, "cancel", "cancel")
    {HTTP::Status::OK, "Success"}
  end

end
