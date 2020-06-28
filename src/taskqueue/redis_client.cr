require "redis"
require "json"

class TaskQueue
  def initialize()
    redis_host = (ENV.has_key?("REDIS_HOST") ? ENV["REDIS_HOST"] : REDIS_HOST)
    redis_port = (ENV.has_key?("REDIS_PORT") ? ENV["REDIS_PORT"].to_i32 : REDIS_PORT)

    @redis = Redis.new(redis_host, redis_port)
  end

  private def get_new_seqno()
    return @redis.incr("#{QUEUE_NAME_BASE}/seqno")
  end

  private def task_in_queue(id : String, queue_name : String)
    data = @redis.hget("#{QUEUE_NAME_BASE}/id2content", id)
    if data.nil?
      return false
    else
      data_hash = JSON.parse(data)
      if (data_hash["queue"].to_s == queue_name)
        return true
      else
        return false
      end
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

    @redis.multi do |multi|
      multi.zadd("#{QUEUE_NAME_BASE}/#{to}", operate_time, id)
      multi.zrem("#{QUEUE_NAME_BASE}/#{from}", id)
      multi.hset("#{QUEUE_NAME_BASE}/id2content", id, content.to_json)
    end

    return content["data"].to_json
  end
end
