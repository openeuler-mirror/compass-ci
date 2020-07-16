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
  def initialize()
    redis_host = (ENV.has_key?("REDIS_HOST") ? ENV["REDIS_HOST"] : REDIS_HOST)
    redis_port = (ENV.has_key?("REDIS_PORT") ? ENV["REDIS_PORT"].to_i32 : REDIS_PORT)

    redis_pool_num = (ENV.has_key?("REDIS_POOL_NUM") ?
                      ENV["REDIS_POOL_NUM"].to_i32 : REDIS_POOL_NUM)

    @redis = Redis::PooledClient.new(host: redis_host,
               port: redis_port, pool_size: redis_pool_num, pool_timeout: 0.01)
  end

  private def get_new_seqno()
    return @redis.incr("#{QUEUE_NAME_BASE}/seqno")
  end

  private def task_in_queue_status(id : String, queue_name : String)
    current_seqno = @redis.get("#{QUEUE_NAME_BASE}/seqno")
    current_seqno = "0" if current_seqno.nil?
    current_seqno = current_seqno.to_i64
    return TaskInQueueStatus::TooBigID  if id.to_i64 > current_seqno

    data = @redis.hget("#{QUEUE_NAME_BASE}/id2content", id)
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
    if content["id"]?
      task_id = content["id"].as_i64
    else
      task_id = get_new_seqno()
      content = content.merge({:id => task_id})
    end
    operate_time = Time.local.to_unix_f
    data = {
      :add_time => operate_time,
      :queue => queue_name,
      :data => content
    }

    # no need watch (id must not eq, so zadd | hset will not duplicate)
    @redis.multi do |multi|
      multi.zadd("#{QUEUE_NAME_BASE}/#{queue_name}", operate_time, task_id)
      multi.hset("#{QUEUE_NAME_BASE}/id2content", task_id, data.to_json)
    end

    return task_id
  end

  private def find_first_task_in_redis(queue_name)
    first_task = @redis.zrange("#{QUEUE_NAME_BASE}/#{queue_name}", 0, 0)
    if first_task.size == 0
      return nil
    else
      return first_task[0].to_s
    end
  end

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
    #   or result will be [1, 1, 1]
    @redis.watch("#{QUEUE_NAME_BASE}/#{from}")
    result = @redis.multi do |multi|
      multi.zadd("#{QUEUE_NAME_BASE}/#{to}", operate_time, id)
      multi.zrem("#{QUEUE_NAME_BASE}/#{from}", id)
      multi.hset("#{QUEUE_NAME_BASE}/id2content", id, content.to_json)
    end

    return nil if result.size < 3

    return content["data"].to_json
  end

  private def move_first_task_in_redis(from : String, to : String)
    first_task_id = Redis::Future.new
    @redis.watch("#{QUEUE_NAME_BASE}/#{from}")
    result = @redis.multi do |multi|
      first_task_id = multi.zrange("#{QUEUE_NAME_BASE}/#{from}", 0, 0)
      multi.zremrangebyrank("#{QUEUE_NAME_BASE}/#{from}", 0, 0)
    end
    return nil if result.size < 2           # caused by watch
    return nil if result[1].as(Int64) == 0  # 0 means no delete == no id

    # result was [[id], 1]
    id = first_task_id.value.as(Array)[0].to_s
    content = find_task(id)
    return nil if content.nil?

    operate_time = Time.local.to_unix_f
    content = content.merge({"queue" => to})
    content = content.merge({"move_time" => operate_time})

    @redis.multi do |multi|
      multi.zadd("#{QUEUE_NAME_BASE}/#{to}", operate_time, id)
      multi.hset("#{QUEUE_NAME_BASE}/id2content", id, content.to_json)
    end

    return content["data"].to_json
  end

  private def delete_task_in_redis(queue : String, id : String)
    content = find_task(id)
    return nil if content.nil?
    return nil if (service_name_of_queue(content["queue"].to_s) != queue)

    # if another hdel first, then the result will be []
    #   or result will be [1, 1]
    @redis.watch("#{QUEUE_NAME_BASE}/#{content["queue"]}")
    result = @redis.multi do |multi|
      multi.zrem("#{QUEUE_NAME_BASE}/#{content["queue"]}", id)
      multi.hdel("#{QUEUE_NAME_BASE}/id2content", id)
    end

    return nil if result.size < 2

    return content["data"].to_json
  end

end
