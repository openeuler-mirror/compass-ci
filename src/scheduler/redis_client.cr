# SPDX-License-Identifier: MulanPSL-2.0+

require "json"
require "redis"

require "./constants"
require "../lib/job"

#require "../lib/redis/src/redis"
# -------------------------------------------------------------------------------------------
# get_new_job_id()
#  - use redis incr as job_id
#
# -------------------------------------------------------------------------------------------

class Redis::Client
    class_property :client
    HOST = (ENV.has_key?("REDIS_HOST") ? ENV["REDIS_HOST"] : JOB_REDIS_HOST)
    PORT = (ENV.has_key?("REDIS_PORT") ? ENV["REDIS_PORT"] : JOB_REDIS_PORT).to_i32

    def initialize(host = HOST, port = PORT)
        @client = Redis.new(host, port) # if redis-server is not ready? here may need raise error
    end

    def key_special_field(key, field)
      case key
      when "sched/mac2host"
         # ignore mac format "ff:ff" | "ff-ff", inner use "ff-ff"
         field_dst = field.to_s.gsub(":", "-")
      else
         field_dst = field.to_s
      end
      return field_dst
    end

    def hash_set(key : String, field, value)
      field_to_set = key_special_field(key, field)
      @client.hset(key, field_to_set, value.to_s)
    end

    def hash_get(key : String, field)
      field_to_get = key_special_field(key, field)
      @client.hget(key, field_to_get)
    end

    # redis incr is a 64bit signed int
    def get_new_job_id()
        sn = @client.incr("sched/seqno2jobid")
        return "#{sn}"
    end

    def get_job(job_id : String)
        job_hash = @client.hget("sched/id2job", job_id)
        if !job_hash
            raise "Get job (id = #{job_id}) from redis failed."
        end
        Job.new(JSON.parse(job_hash))
    end

    def update_wtmp(testbox : String, wtmp_hash : Hash)
        @client.hset("sched/tbox_wtmp", testbox, wtmp_hash.to_json)
    end

    def update_job(job_content : JSON::Any | Hash)
        job_id = job_content["id"].to_s

        job = get_job(job_id)
        job.update(job_content)

        hash_set("sched/id2job", job_id, job.dump_to_json)
    end

    def set_job(job : Job)
        hash_set("sched/id2job", job.id, job.dump_to_json)
    end

    def add2queue(queue_name : String, job_id : String)
        # add job to queue with priority (based on time)
        job_list = queue_name

        # priority must be NOT eq
        priority_as_score = Time.local.to_unix_f
        @client.zadd(job_list, priority_as_score, job_id)

        return priority_as_score
    end

    def find_job_in_queue(queue_name : String)
        # check the first order job_id
        first_job = @client.zrange(queue_name, 0, 0)

        # this queue has no job
        if first_job.size == 0
            return "0"
        end

        return first_job[0]
    end

    # move job atomiclly
    def move_job(queue_name_from : String, queue_name_to : String)
        lua_script = "local job =  redis.call('zrange', KEYS[1], 0, 0)
        if table.getn(job) == 0 then
            return '0'
        else
            redis.call('zadd', KEYS[2], ARGV[1], job[1])
            redis.call('zrem', KEYS[1], job[1])
            return job[1]
        end"

        priority_as_score = Time.local.to_unix_f

        @client.eval(lua_script, [queue_name_from, queue_name_to], [priority_as_score])
    end

    def remove_finished_job(job_id : String)
        @client.hdel("sched/id2job", job_id)
    end

    def find_id(hostname : String)
        respon = @client.hgetall("sched/id2job")
        len = respon.size / 2

        key = nil
        len.to_i.times do |index|
            value = JSON.parse(respon[0 * index + 1].to_s)["testbox"]
            if (value.to_s == hostname)
                key = respon[0 * index].to_s
                break
            end
        end

        return key
    end
end
