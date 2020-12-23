# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def download_file
    job_id = @env.params.url["job_id"]
    job_package = @env.params.url["job_package"]
    file_path = ::File.join [Kemal.config.public_folder, job_id, job_package]

    @log.info(%({"job_id": "#{job_id}", "job_state": "download"}))

    send_file @env, file_path
  rescue e
    @log.warn(e)
  end
end
