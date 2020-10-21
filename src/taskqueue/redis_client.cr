# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "redis"
require "json"

#  redis key like: queues/service/subkey/ready|in_process
# queue name like:        service/[.../]subkey
enum TaskInQueueStatus
  TooBigID    # 0
  NotExists   # 1
  SameQueue   # 2, match with [queues/]service/[.../]queue
  SameService # 3, match with [queues/]service
  InTaskQueue # 4, match with [queues/]
end

class TaskQueue
  def initialize
    redis_host = (ENV.has_key?("REDIS_HOST") ? ENV["REDIS_HOST"] : REDIS_HOST)
    redis_port = (ENV.has_key?("REDIS_PORT") ? ENV["REDIS_PORT"].to_i32 : REDIS_PORT)

    redis_pool_num = (ENV.has_key?("REDIS_POOL_NUM") ? ENV["REDIS_POOL_NUM"].to_i32 : REDIS_POOL_NUM)

    redis_pool_timeout = (ENV.has_key?("REDIS_POOL_TIMEOUT") ? ENV["REDIS_POOL_TIMEOUT"].to_i32 : REDIS_POOL_TIMEOUT)

    @redis = Redis::PooledClient.new(host: redis_host,
      port: redis_port, pool_size: redis_pool_num,
      pool_timeout: redis_pool_timeout / 1000)
  end

  private def get_new_seqno
    return @redis.incr("#{QUEUE_NAME_BASE}/seqno")
  end

  private def task_in_queue_status(id : String, queue_name : String)
    current_seqno = @redis.get("#{QUEUE_NAME_BASE}/seqno")
    current_seqno = "0" if current_seqno.nil?
    current_seqno = current_seqno.to_i64
    return TaskInQueueStatus::TooBigID if id.split('.')[-1].to_i64 > current_seqno

    data_f = Redis::Future.new
    loop_till_done() {
      @redis.watch("#{QUEUE_NAME_BASE}/id2content")
      op_result = @redis.multi do |multi|
        data_f = multi.hget("#{QUEUE_NAME_BASE}/id2content", id)
      end
      op_result
    }
    data = data_f.value.as(String?)
    return TaskInQueueStatus::NotExists if data.nil?

    data_hash = JSON.parse(data)
    data_queue = data_hash["queue"].to_s
    return TaskInQueueStatus::SameQueue if data_queue == queue_name

    if service_name_of_queue(data_queue) == service_name_of_queue(queue_name)
      return TaskInQueueStatus::SameService
    else
      return TaskInQueueStatus::InTaskQueue
    end
  end

  private def add2redis(queue_name : String, content : Hash)
    operate_time = Time.local.to_unix_f # do prepare thing early

    if content["id"]?
      # this means we'll add like duplicate id
      #  will operate to same redis key (queues/id2content)
      task_id = content["id"]
    else
      task_id = "#{content["lab"]}.#{get_new_seqno()}"
      content = content.merge({:id => task_id})
    end
    data = {
      :add_time => operate_time,
      :queue    => queue_name,
      :data     => content,
    }

    loop_till_done() {
      @redis.watch("#{QUEUE_NAME_BASE}/id2content")
      op_result = @redis.multi do |multi|
        multi.zadd("#{QUEUE_NAME_BASE}/#{queue_name}", operate_time, task_id)
        multi.hset("#{QUEUE_NAME_BASE}/id2content", task_id, data.to_json)
      end
      op_result
    }

    return task_id
  end

  # need loop_till_done ?
  private def find_first_task_in_redis(queue_name)
    first_task = @redis.zrange("#{QUEUE_NAME_BASE}/#{queue_name}", 0, 0)
    if first_task.size == 0
      return nil
    else
      return first_task[0].to_s
    end
  end

  # need loop_till_done ?
  private def find_task(id : String)
    task_content_raw = @redis.hget("#{QUEUE_NAME_BASE}/id2content", id)
    if task_content_raw.nil?
      return nil
    else
      return JSON.parse(task_content_raw).as_h
    end
  end

  private def move_task_in_redis(from : String, to : String, id : String)
    content = find_task(id)
    return nil if content.nil?
    return nil if (content["queue"] != from)

    operate_time = Time.local.to_unix_f
    content = content.merge({"queue" => to})
    content = content.merge({"move_time" => operate_time})

    # if another zrem first, then the result will be []
    #   or result will be [1, 1, 1|0]
    result = loop_till_done() {
      @redis.watch("#{QUEUE_NAME_BASE}/#{from}")
      op_result = @redis.multi do |multi|
        multi.zadd("#{QUEUE_NAME_BASE}/#{to}", operate_time, id)
        multi.zrem("#{QUEUE_NAME_BASE}/#{from}", id)
        multi.hset("#{QUEUE_NAME_BASE}/id2content", id, content.to_json)
      end
      op_result
    }
    if (result.not_nil![0] != 1) || (result.not_nil![1] != 1)
      puts "#{Time.utc} WARN -- operate error in move task."
    end

    return content["data"].to_json
  end

  private def move_first_task_in_redis(from : String, to : String)
    first_task_id = Redis::Future.new
    result = loop_till_done() {
      @redis.watch("#{QUEUE_NAME_BASE}/#{from}")
      op_result = @redis.multi do |multi|
        first_task_id = multi.zrange("#{QUEUE_NAME_BASE}/#{from}", 0, 0)
        multi.zremrangebyrank("#{QUEUE_NAME_BASE}/#{from}", 0, 0)
      end
      op_result
    }
    return nil if result.not_nil![1].as(Int) == 0 # 0 means no delete == no id

    # result was [[id], 1]
    id = first_task_id.value.as(Array)[0].to_s
    content = find_task(id)
    return nil if content.nil?

    operate_time = Time.local.to_unix_f
    content = content.merge({"queue" => to})
    content = content.merge({"move_time" => operate_time})

    loop_till_done() {
      @redis.multi do |multi|
        multi.zadd("#{QUEUE_NAME_BASE}/#{to}", operate_time, id)
        multi.hset("#{QUEUE_NAME_BASE}/id2content", id, content.to_json)
      end
    }

    return content["data"].to_json
  end

  private def delete_task_in_redis(queue : String, id : String)
    content = find_task(id)
    return nil if content.nil?
    return nil if (service_name_of_queue(content["queue"].to_s) != queue)

    # if another hdel first, then the result will be []
    #   or result will be [1, 1]
    loop_till_done() {
      @redis.watch("#{QUEUE_NAME_BASE}/#{content["queue"]}")
      op_result = @redis.multi do |multi|
        multi.zrem("#{QUEUE_NAME_BASE}/#{content["queue"]}", id)
        multi.hdel("#{QUEUE_NAME_BASE}/id2content", id)
      end
      op_result
    }

    return content["data"].to_json
  end

  # when use redis PooledClient and <watch, multi> command,
  #   there maybe a conflict need to fix:
  #   1) thread-1 try to find something that thread-2 will write in
  #   2) thread-3 may do write too, and this will make thread-2
  #      can do write at first time
  # so we need let the thread-2's command retry as soon as possible.
  #
  # loop until there has no operate conflict
  #   when use redis.watch(keys) command, if another
  #     thread is modify the key, all redis.multi
  #     command will not do. that returns [].
  #   when no conflict, all redis.multi command will
  #     be done. return [result, ...] for each command.
  #
  # yield block like this
  # {
  #   redis.watch
  #   op_result = redis.multi do |multi|
  #   end
  #   op_result   <- this value will return
  # }
  #
  # connect pool timeout is 0.01 second (10 ms)
  #   here keep try for 30ms
  private def loop_till_done
    result = nil
    time_start = Time.local.to_unix_ms

    # i = 0
    loop do
      result = yield
      break if result.size > 0
      # i = i + 1
      if (Time.local.to_unix_ms - time_start) > 30
        # there should only retry 1-2 times
        puts "#{Time.utc} WARN -- should not retry so long."
        break
      end
    end

    # call record: 5208 times of command
    #              115 times of retry
    #  max retried 7 times ( occurence 1 times)
    # p "retry #{i} times"
    return result
  end

  private def get_uuid_keys(queue_name)
    return nil unless queue_name[0..5] == "sched/"

    # search = "queues/sched/vm-2p8g/ee44b164-90e3-49a7-9798-5e7cc9bc7451"
    # only 3 matchs keyword: * [] ?
    search = "#{QUEUE_NAME_BASE}/#{queue_name}/[0-9a-eA-F\-]*"
    lua_script = "return redis.call('keys', KEYS[1])"
    keys = @redis.eval(lua_script, [search])

    case keys
    when Array(Redis::RedisValue)
      return nil unless keys.size > 0
    else
      return nil
    end

    keys.each do |key|
      # must end with uuid, then keep it
      #  some queue name that has "uuid" at middle, also will delete
      uuid, _ = get_matched_queue_name(key)
      case uuid
      when "idle", "ready"
        keys.delete(key)
      end
    end
    return keys
  end

  private def get_keys(queue_name)
    query_prefix = QUEUE_NAME_BASE + "/"
    query_prefix_len = query_prefix.size
    search = query_prefix + queue_name
    response = [] of String

    cursor = "0"
    loop do
      cursor, keys = @redis.scan(cursor, search, 256)
      case keys
      when Array(Redis::RedisValue)
        keys.each do |key|
          response << "#{key}"[query_prefix_len..-1]
        end
      end

      break if cursor == "0"
    end

    return response
  end

  private def move_first_task_in_redis_with_score(from : String, to : String)
    # result was ["crystal.87230", "1600782938.9017849"]
    result = @redis.zrange("#{QUEUE_NAME_BASE}/#{from}", 0, 0, with_scores: true)
    case result
    when Array(Redis::RedisValue)
      # empty queue will be auto delete by redis
      return if result.size != 2
    else
      return
    end

    @redis.zremrangebyrank("#{QUEUE_NAME_BASE}/#{from}", 0, 0)
    content = find_task(result[0].to_s)
    return if content.nil?

    operate_time = Time.local.to_unix_f
    content = content.merge({"queue" => to})
    content = content.merge({"move_with_score_time" => operate_time})

    @redis.zadd("#{QUEUE_NAME_BASE}/#{to}", result[1], result[0])
    @redis.hset("#{QUEUE_NAME_BASE}/id2content", result[0], content.to_json)

    # return content["data"].to_json
  end
end
