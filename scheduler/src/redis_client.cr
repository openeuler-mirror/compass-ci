require "redis"
require "./tools"
#require "../lib/redis/src/redis"
# -------------------------------------------------------------------------------------------
# get_new_job_id()
#  - use redis incr as job_id
#
# -------------------------------------------------------------------------------------------
# moveJob(queue_name_from : String, queue_name_to : String, job_id : String)
#  - move job from queue_name_from to [queue_name_to], data type is a redis sorted set
#  - example : moveJob("sched/jobs_to_run/$tbox_group", "sched/jobs_running", "12")
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
        priorityAsScore = Time.local.to_unix_f
        @client.zadd(job_list, priorityAsScore, job_id)

        return priorityAsScore
    end

    # pending queue name is sched/jobs_to_run/$tbox_group
    def findAnyJob(tbox_group : String)
        job_list = "sched/jobs_to_run/#{tbox_group}"
        job_id = findJobInQueue(job_list)
        return job_id, job_list
    end

    def findJobInQueue(queue_name : String)
        # check the first order job_id
        first_job = @client.zrange(queue_name, 0, 0)

        # this queue has no job
        if first_job.size == 0
            return "0"
        end

        return first_job[0]
    end

    def jsonAppend(key, job_id, append)
        json_append = JSON.parse(append.not_nil!)
        orange_text = @client.hget(key, job_id)
        if (orange_text != nil)
            json_orange = JSON.parse(orange_text.not_nil!)
            result = json_orange.as_h.merge(json_append.as_h)
             return @client.hset(key, job_id, result.to_json)
        else
            return @client.hset(key, job_id,  append)
        end
    end

    def moveJob(queue_name_from : String, queue_name_to : String, job_id : String)
        @client.zrem(queue_name_from, job_id)
        priorityAsScore = Time.local.to_unix_f

        # queue_name_to: sched/jobs_running
        @client.zadd(queue_name_to, priorityAsScore, job_id)

        return priorityAsScore
    end

    def updateRunningInfo(job_id : String, infomation)
        jsonAppend("sched/id2job", job_id, infomation)
    end

    def removeRunning(job_id : String)
        @client.zrem("sched/jobs_running", job_id)
        @client.hdel("sched/id2job", job_id)
    end

    def findID(hostname : String)
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
