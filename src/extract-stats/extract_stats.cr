# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../lib/etcd_client"
require "./constants"
require "./stats_worker"

module ExtractStats
  @@ec = EtcdClient.new
  @@commit_channel = Channel(String).new

  def self.consume_tasks
    channel = Channel(String).new
    queue = EXTRACT_STATS_QUEUE_PATH
    revision = self.consume_by_list(queue, channel)
    self.consume_by_watch(queue, revision, channel)
  end

  def self.consume_by_list(queue, channel)
    tasks, revision = self.get_history_tasks(queue)
    self.handle_history_tasks(tasks, channel)

    return revision
  end

  def self.consume_by_watch(queue, revision, channel)
    self.watch_queue(queue, revision, channel)
    self.handle_events(channel)
  end

  def self.get_history_tasks(queue)
    tasks = [] of Etcd::Model::Kv
    range = @@ec.range_prefix(queue)
    revision = range.header.not_nil!.revision
    tasks += range.kvs

    return tasks, revision
  end

  def self.handle_history_tasks(tasks, channel)
    while true
      return if tasks.empty?

      task = tasks.delete_at(0)
      spawn { StatsWorker.new.handle(task.key, channel, @@commit_channel) }
      Fiber.yield
    end
  end

  def self.watch_queue(queue, revision, channel)
    watcher = EtcdClient.new.watch_prefix(queue, start_revision: revision.to_i64 + 1, filters:  [Etcd::Watch::Filter::NODELETE]) do |events|
      events.each do |event|
        puts event
        channel.send(event.kv.key)
      end
    end

    spawn { watcher.start }
    Fiber.yield
  end

  def self.handle_events(channel)
    while true
      key = channel.receive
      spawn { StatsWorker.new.handle(key, channel, @@commit_channel) }
      Fiber.yield
    end
  end
end
