# SX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "singleton"

require "./etcd_client"
require "./common"
require "./json_logger"

class Queue
  def self.instance
    Singleton::Of(self).instance
  end

  def initialize
    @log = JSONLogger.new
    @etcd = EtcdClient.new
    @mutexes = Hash(String, Mutex).new
    @queues = Hash(String, Hash(String, Array(Etcd::Model::Kv))).new
    @revisions = Hash(String, Int64).new
  end

  def update_one_queue(queue)
    response = @etcd.range_prefix(queue, 100)
    jobs = Common.split_jobs_by_subqueue(response.kvs)
    @queues[queue] = reverse_jobs(jobs)
    @revisions[queue] = response.header.not_nil!.revision
  end

  def reverse_jobs(jobs)
    res = Hash(String, Array(Etcd::Model::Kv)).new
    jobs.each do |subqueue, job_list|
      res[subqueue] = job_list.reverse
    end
    return res
  end

  def get_min_revision(queues)
    revisions = Array(Int64).new
    queues.each do |queue|
      revisions << @revisions[queue] if @revisions[queue]?
    end
    return revisions.min
  end

  def should_update(queue)
    return true unless @queues[queue]?
    return false if @queues[queue].empty?

    queue_empty?(queue)
  end

  def init_one_queue(queue, mutex)
    return unless should_update(queue)

    mutex.lock
    begin
      update_one_queue(queue) if should_update(queue)
    ensure
      mutex.unlock
    end
  end

  def init_queues(queues)
    queues.each do |queue|
      @mutexes[queue] ||= Mutex.new
      init_one_queue(queue, @mutexes[queue])
    end
  end

  def get_subqueue_set(queue)
    subqueues = @queues[queue]? || Hash(String, String).new
    subqueues.keys.to_set
  end

  def pop_one_job(queue, subqueue)
    return nil unless @queues[queue]?
    return nil unless @queues[queue][subqueue]?

    @queues[queue][subqueue].pop
  rescue IndexError
    return nil
  end

  def queues_empty?(queues)
    queues.each do |queue|
      return false unless queue_empty?(queue)
    end
    return true
  end

  def queue_empty?(queue)
    return true unless @queues[queue]?

    @queues[queue].each do |_, jobs|
      return false unless jobs.empty?
    end
    return true
  end

  def timing_refresh_from_etcd
    while true
      sleep(60)
      @queues.each_key do |k|
        update_one_queue(k)
      rescue e
        @log.warn({
          "message" => "update one queue failed: #{k}",
          "error_message" => e.inspect_with_backtrace.to_s
        }.to_json)
      end
      @log.info("timing_refresh_from_etcd success")
    end
  end
end
