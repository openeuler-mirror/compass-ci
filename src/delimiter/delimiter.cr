# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require "../lib/etcd_client"

class Delimiter
  def initialize
    @ec = EtcdClient.new
  end

  def consume_delimiter(queue)
    channel = Channel(Etcd::Model::Kv).new
    revision = consume_by_list(queue, channel)
    consume_by_watch(queue, revision, channel)
  end

  def consume_by_list(queue, channel)
    tasks, revision = get_history_tasks(queue)
    handle_history_tasks(tasks, channel)

    return revision
  end

  def consume_by_watch(queue, revision, channel)
    watch_queue(queue, revision, channel)
    handle_events(channel)
  end

  def get_history_tasks(queue)
    tasks = [] of Etcd::Model::Kv
    range = @ec.range_prefix(queue)
    revision = range.header.not_nil!.revision
    tasks += range.kvs

    return tasks, revision
  end

  def handle_history_tasks(tasks, channel)
    loop do
      return if tasks.empty?

      task = tasks.delete_at(0)
      spawn { submit_bisect_job(channel, task) }
    end
  end

  def watch_queue(queue, revision, channel)
    watcher = EtcdClient.new.watch_prefix(queue, start_revision: revision.to_i64 + 1, filters:  [Etcd::Watch::Filter::NODELETE]) do |events|
      events.each do |event|
        channel.send(event.kv)
      end
    end

    spawn { watcher.start }
    Fiber.yield
  end

  def handle_events(channel)
    loop do
      task = channel.receive
      spawn { submit_bisect_job(channel, task) }
    end
  end

  def submit_bisect_job(channel, task)
    key = task.key
    value = Hash(String, String).from_json(task.value.not_nil!)
    begin
      response = %x(#{ENV["LKP_SRC"]}/sbin/submit bad_job_id=#{value["job_id"]} error_id=#{value["error_id"].inspect} bisect.yaml queue=dc-bisect)
      puts response
      if /id=0/ =~ response
        channel.send(task)
        return
      end

      @ec.delete(key)
    rescue ex
      puts ex
      channel.send(task)
    end
  end
end
