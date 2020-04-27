require "redis"
require "./tools"

# -------------------------------------------------------------------------------------------
# getSN()
#  - use redis incr as job_id
#
# -------------------------------------------------------------------------------------------
# moveJob(queue_name_from : String, queue_name_to : String, job_id : String, append = nil)
#  - move job from queue_name_from to [queue_name_to], data type is a redis sorted set
#  - record append info in hi_[queue_name_to], data type is redis hash
#  - example : moveJob("testgroup_myhost", "running", "12", "myhost-001")
#

class Redis::Client
    class_property :port
    class_property :host

    def initialize(host : String, port : Int32)
        @host = host
        @port = port
    end

    # redis incr is a 64bit signed int
    def getSN()
        begin
            client = Redis.new(@host, @port)
            sn = client.incr("global_job_id")
            client.close
            return "#{sn}"
        rescue exception  # mostly caused by connect failed
            return "0"
        end
    end

    def id2name(queue_id : Int32)
        return "sorted_job_list_#{queue_id}"
    end

    def add2queue(queue_id : Int32, job_id : String)
        return add2queue(id2name(queue_id), job_id)
    end

    def add2queue(queue_name : String, job_id : String)
        begin
            # add job to queue with priority (based on time)
            client = Redis.new(@host, @port)
            job_list = queue_name

            # priority must be NOT eq
            priorityAsScore = Time.local.to_unix_f
            client.zadd(job_list, priorityAsScore, job_id)

            client.close
            return priorityAsScore
        rescue exception  # mostly caused by connect failed
            return 0
        end
    end

    # pending queue name is sorted_job_list_
    def findAnyJob(queue_id : Int32)
        job_list = "sorted_job_list_#{queue_id}"
        job_id = findJobInQueue(job_list)
        return job_id, job_list
    end

    # pending queue name is testgroup_
    def findAnyJob(testgroup : String)
        job_list = "testgroup_#{testgroup}"
        return findJobInQueue(job_list), job_list
    end

    def findJobInQueue(queue_name : String)
        client = Redis.new(@host, @port)

        # check the first order job_id
        first_job = client.zrange(queue_name, 0, 0)

        # this queue has no job
        if first_job.size == 0
            return "0"
        end

        client.close
        return first_job[0]
    end

    def jsonAppend(client, key, job_id, append)
        json_append = JSON.parse(append.not_nil!)
        orange_text = client.hget(key, job_id)
        if (orange_text != nil)
            json_orange = JSON.parse(orange_text.not_nil!)
            result = json_orange.as_h.merge(json_append.as_h)
             return client.hset(key, job_id, result.to_json)
        else
            return client.hset(key, job_id,  append)
        end
    end

    def moveJob(queue_name_from : String, queue_name_to : String, job_id : String, append = nil)
        begin
            client = Redis.new(@host, @port)
            client.zrem(queue_name_from, job_id)

            priorityAsScore = Time.local.to_unix_f

            # queue_name_to: running and helpinfo hi_running
            client.zadd(queue_name_to, priorityAsScore, job_id)
            if (append)
                jsonAppend(client, "hi_#{queue_name_to}", job_id, %({"testbox":"#{append}"}))
            end

            client.close
            return priorityAsScore
        rescue exception  # mostly caused by connect failed
            puts exception
            return 0
        end
    end

    def updateRunningInfo(job_id : String, infomation)
        begin
            client = Redis.new(@host, @port)
            jsonAppend(client, "hi_running", job_id, infomation)
            client.close
            return 0
        rescue exception  # mostly caused by connect failed
            puts exception
            return 0
        end
    end

    def removeRunning(job_id : String)
        begin
            client = Redis.new(@host, @port)

            client.zrem("running", job_id)
            client.hdel("hi_running", job_id)

            client.close
            return 0
        rescue exception  # mostly caused by connect failed
            puts exception
            return 0
        end
    end

    def findID(hostname : String)
        begin
            client = Redis.new(@host, @port)

            respon = client.hgetall("hi_running")
            len = respon.size / 2

            key = nil
            len.to_i.times do |index|
                value = JSON.parse(respon[0 * index + 1].to_s)["testbox"]
                if (value.to_s == hostname)
                    key = respon[0 * index].to_s
                    break
                end
            end

            client.close
            return key
        rescue exception  # mostly caused by connect failed
            puts exception
            return 0
        end
    end

    def testConnect()
        client = Redis.new(@host, @port)
        return "--[#{@host}:#{@port}]-- info:\n#{client.info}"
    end

end
