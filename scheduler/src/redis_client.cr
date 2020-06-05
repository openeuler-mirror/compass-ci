require "redis"
require "./tools"
#require "../lib/redis/src/redis"
# -------------------------------------------------------------------------------------------
# get_new_job_id()
#  - use redis incr as job_id
#
# -------------------------------------------------------------------------------------------
# move_job(queue_name_from : String, queue_name_to : String, job_id : String)
#  - move job from queue_name_from to [queue_name_to], data type is a redis sorted set
#  - example : move_job("sched/jobs_to_run/$tbox_group", "sched/jobs_running", "12")
#

class Redis::Client
    class_property :client

    def initialize(host : String, port : Int32)
        @client = Redis.new(host, port) # if redis-server is not ready? here may need raise error
    end

    # redis incr is a 64bit signed int
    def get_new_job_id()
        sn = @client.incr("sched/seqno2jobid")
        return "#{sn}"
    end

    def add2queue(queue_name : String, job_id : String)
        # add job to queue with priority (based on time)
        job_list = queue_name

        # priority must be NOT eq
        priority_as_score = Time.local.to_unix_f
        @client.zadd(job_list, priority_as_score, job_id)

        return priority_as_score
    end

    # pending queue name is sched/jobs_to_run/$tbox_group
    def find_any_job(tbox_group : String)
        job_list = "sched/jobs_to_run/#{tbox_group}"
        job_id = find_job_in_queue(job_list)
        return job_id, job_list
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

    def move_job(queue_name_from : String, queue_name_to : String, job_id : String)
        @client.zrem(queue_name_from, job_id)
        priority_as_score = Time.local.to_unix_f

        # queue_name_to: sched/jobs_running
        @client.zadd(queue_name_to, priority_as_score, job_id)

        return priority_as_score
    end

    def add_job_content(job_content)
        job_id = job_content["id"]
        job_content_o = get_job_content("#{job_id}")
        job_content_m = job_content_o.merge(job_content)

        @client.hset("sched/id2job", job_id, job_content_m.to_json)
    end

    def get_job_content(job_id)
        job_content = @client.hget("sched/id2job", job_id)
        if job_content.nil?
            job_content = Hash(String, String).new
        else
            job_content = JSON.parse(job_content).as_h
        end
        return job_content
    end

    def remove_running(job_id : String)
        @client.zrem("sched/jobs_running", job_id)
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
