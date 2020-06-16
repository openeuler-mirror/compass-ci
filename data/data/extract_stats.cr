require "../../scheduler/scheduler/redis_client"
require "../../scheduler/scheduler/constants"
require "./constants"

#results data post processing

redis_host = (ENV.has_key?("REDIS_HOST") ? ENV["REDIS_HOST"] : JOB_REDIS_HOST)
redis_port = (ENV.has_key?("REDIS_PORT") ? ENV["REDIS_PORT"] : JOB_REDIS_PORT).to_i32

data_extract_queue = DATA_EXTRACT_QUEUE
scheduler_extract_queue = SCHEDULER_EXTRACT_QUEUE

def consume_scheduler_queue(redis_client : Redis::Client, data_queue : String, scheduler_queue : String)
    loop do
        job_id= redis_client.move_job(scheduler_queue, data_queue)
        if job_id != "0"
            #extract_stats
            redis_client.@client.zrem(data_queue , "#{job_id}")
        else
            sleep(1)
            next
        end
    end
end

redis_client = Redis::Client.new(redis_host, redis_port)
consume_scheduler_queue(redis_client, data_extract_queue, scheduler_extract_queue)
