# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../lib/queue"
require "../lib/subqueue"
require "../lib/etcd_client"
require "../lib/job"
require "../lib/common"

class ConsumeJob
  def initialize
    @queue = Queue.instance
    @subqueue = Subqueue.instance
    @etcd = EtcdClient.new
    @pre_job = nil
    @es = nil
  end

  def set_no_reboot(job : Job)
    @pre_job = job
    @es = Elasticsearch::Client.new
  end

  def consume_by_priority(queue)
    job = nil
    state = nil
    job_subqueue_set = @queue.get_subqueue_set(queue)
    (0..9).each do |i|
      subqueues = @subqueue.get_priority2subqueue(i) & job_subqueue_set
      next if subqueues.empty?

      job_subqueue_set -= subqueues

      job, state = consume_by_weight(subqueues, queue)
      break if job
    end

    return job, state if job || job_subqueue_set.empty?

    # some subqueues have no priority
    consume_by_weight(job_subqueue_set, queue)
  end

  def consume_by_weight(subqueues, queue)
    subqueue_list = Array(String).new
    subqueues.each do |subqueue|
      subqueue_list += [subqueue] * @subqueue.get_weight(subqueue)
    end
    subqueue_list.shuffle!
    consume_job(subqueue_list, queue)
  end

  def consume_job(subqueue_list, queue)
    job = nil
    state = nil

    loop do
      return nil, state if subqueue_list.empty?

      subqueue = subqueue_list.pop
      loop do
        job = @queue.pop_one_job(queue, subqueue)
        break unless job

        if @pre_job
          state = "job mismatch"
          next unless Common.match_no_reboot?(job, @pre_job.as(Job), @es.as(Elasticsearch::Client))
        end
        return job, nil if move_job_to_process(job)
      end
    end
  end

  def consume_history_job(queues)
    job = nil
    state = nil
    # priority jobs with high matching degree of consumption queue
    queues.sort_by {|queue| -queue.size}

    queues.each do |queue|
      job, state = consume_by_priority(queue)
      break if job
    end

    return job, state
  ensure
    @etcd.close
  end

  def move_job_to_process(job)
    f_queue = job.key
    tmp = f_queue.split("/")
    if "ready" == tmp[3]
      t_queue = f_queue.gsub("/ready/", "/in_process/")
    else
      tmp = f_queue.split("/")
      tmp.delete("ready")
      tmp.insert(3, "in_process")
      t_queue = tmp.join("/")
    end
    value = job.value
    @etcd.move(f_queue, t_queue, value)
  end
end
