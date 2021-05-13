# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../lib/etcd_client"
require "./constants"
require "./stats_worker"
require "../scheduler/redis_client"
require "../scheduler/elasticsearch_client"

module ExtractStats
  @@ec = EtcdClient.new

  def self.consume_tasks
    channel = Channel(String).new
    commit_channel = Channel(String).new
    queue = EXTRACT_STATS_QUEUE_PATH
    spawn { self.handle_upstream_commit(commit_channel) }
    revision = self.consume_by_list(queue, channel, commit_channel)
    self.consume_by_watch(queue, revision, channel, commit_channel)
  end

  def self.consume_by_list(queue, channel, commit_channel)
    tasks, revision = self.get_history_tasks(queue)
    self.handle_history_tasks(tasks, channel, commit_channel)

    return revision
  end

  def self.consume_by_watch(queue, revision, channel, commit_channel)
    self.watch_queue(queue, revision, channel)
    self.handle_events(channel, commit_channel)
  end

  def self.get_history_tasks(queue)
    tasks = [] of Etcd::Model::Kv
    range = @@ec.range_prefix(queue)
    revision = range.header.not_nil!.revision
    tasks += range.kvs

    return tasks, revision
  end

  def self.handle_history_tasks(tasks, channel, commit_channel)
    while true
      return if tasks.empty?

      task = tasks.delete_at(0)
      spawn { StatsWorker.new.handle(task.key, channel, commit_channel) }
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

  def self.handle_events(channel, commit_channel)
    while true
      key = channel.receive
      spawn { StatsWorker.new.handle(key, channel, commit_channel) }
      Fiber.yield
    end
  end

  # mail compare result between upstream_commit and base_commit
  def self.handle_upstream_commit(commit_channel)
    queue = "queues/#{MAIL_COMPARE_QUEUE}"
    redis = Redis::Client.new
    es = Elasticsearch::Client.new

    while true
      upstream_commit = commit_channel.receive
      job_nr_run = get_job_nr_run(es, upstream_commit)
      run_times = move_upstream_commit(redis, queue, upstream_commit)
      next unless job_nr_run
      next if run_times < job_nr_run

      system "#{ENV["CCI_SRC"]}/sbin/mail-compare #{upstream_commit}"

      redis.hash_del(queue, upstream_commit)
    end
  end
end

def move_upstream_commit(redis, queue, upstream_commit)
  nr_run = redis.@client.hget(queue, upstream_commit)
  if nr_run
    nr_run = nr_run.to_i
    nr_run += 1
    redis.@client.hset(queue, upstream_commit, nr_run)
  else
    nr_run = 1
    redis.@client.hset(queue, upstream_commit, nr_run)
  end

  nr_run
end

# get one job[nr_run] by upstream_commit
def get_job_nr_run(es, upstream_commit)
  query_body = {
    "query" => {
      "term" => {
        "upstream_commit" => upstream_commit,
      }
    },
    "size" => 3,
  }
  result = es.@client.search({
    :index => "jobs",
    :type  => "_doc",
    :body  => query_body,
  })

  source = result["hits"]["hits"][0]
  return nil unless source.is_a?(JSON::Any)

  source["_source"]["nr_run"].as_i
end
