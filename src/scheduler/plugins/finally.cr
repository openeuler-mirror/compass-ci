# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "./plugins_common"

class Finally < PluginsCommon
  def handle_job(job)
    return if job.added_by?

    job.added_by = ["finally"]
    save_job2es(job)
    save_job2etcd(job)
    add_job2custom(job)
  end

  def add_job2queue(job)
    job.added_by = ["finally"]
    key = "sched/ready/#{job.queue}/#{job.subqueue}/#{job.id}"
    value = { "id" => job.id }

    response = @etcd.put(key, value.to_json)
    raise "add the job to queue failed: id #{job.id}, queue #{key}" unless response
  end

end
