# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def update_id2job(delta_job)
    id = delta_job.id
    job = get_id2job(id)
    return false unless job

    job.merge!(delta_job)
    @etcd.update("sched/id2job/#{id}", job.shrink_to_etcd_fields.to_json)
  end

  def set_id2job(job : Job)
    @etcd.put("sched/id2job/#{job.id}", job.shrink_to_etcd_fields.to_json)
  end

  def get_id2job(id)
    response = @etcd.range("sched/id2job/#{id}")
    return nil unless response.count == 1

    Job.new(JSON.parse(response.kvs[0].value.not_nil!).as_h, id)
  end

  def delete_id2job(id)
    @etcd.delete("sched/id2job/#{id}")
  end

  def move_process2stats(job : Job)
    f_queue = "sched/in_process/#{job.queue}/#{job.subqueue}/#{job.id}"
    t_queue = "extract_stats/#{job.id}"
    value = { "id" => "#{job.id}" }
    ret = @etcd.move(f_queue, t_queue, value)
    return ret if ret

    f_queue = "sched/#{job.queue}/in_process/#{job.subqueue}/#{job.id}"
    @etcd.move(f_queue, t_queue, value)
  end

  def move_process2extract(job : Job)
    f_queue = "/queues/sched/in_process/#{job.host_machine}/#{job.id}"
    t_queue = "extract_stats/#{job.id}"
    value = { "id" => "#{job.id}" }
    ret = @etcd.move(f_queue, t_queue, value.to_json)
    @log.info("move in_process to extract in_process: #{f_queue}, extract: #{t_queue}, ret: #{ret}")
    return ret if ret
  end
end
