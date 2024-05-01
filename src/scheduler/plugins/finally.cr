# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "./plugins_common"

class Finally < PluginsCommon
  def handle_job(job)
    return if job.hash_array.has_key?("added_by")

    save_job2es(job)
    save_job2etcd(job)
    add_job2custom(job)
  end

  def add_job2queue(job)
    job.hash_array["added_by"] = ["finally"]
    key = "sched/ready/#{job.queue}/#{job.subqueue}/#{job.id}"
    value = { "id" => job.id }

    response = @etcd.put(key, value.to_json)
    raise "add the job to queue failed: id #{job.id}, queue #{key}" unless response
  end

  def add_job2custom(job)
    job.hash_array["added_by"] = ["finally"]
    if job.docker_image?
      key = "sched/submit/dc-custom/#{job.id}"
    elsif job.testbox.starts_with?("vm")
      key = "sched/submit/vm-custom/#{job.id}"
    else
      key = "sched/submit/hw-#{job.tbox_group}/#{job.id}"
    end

    job.max_duration ||= "5"
    job.memory_minimum ||= "16"

    value = {
      "id" => JSON::Any.new(job.id.to_s),
      "max_duration" => JSON::Any.new(job.max_duration),
      "memory_minimum" => JSON::Any.new(job.memory_minimum)
    }

    response = @etcd.put(key, value.to_json)
    raise "add the job to queue failed: id #{job.id}, queue #{key}" unless response
  end
end
