require "./scheduler/redis_client"
require "./scheduler/constants"
require "./extract-stats/constants"
require "./scheduler/elasticsearch_client"

# results data post processing

redis_host = (ENV.has_key?("REDIS_HOST") ? ENV["REDIS_HOST"] : JOB_REDIS_HOST)
redis_port = (ENV.has_key?("REDIS_PORT") ? ENV["REDIS_PORT"] : JOB_REDIS_PORT).to_i32

data_extract_queue = DATA_EXTRACT_QUEUE
scheduler_extract_queue = SCHEDULER_EXTRACT_QUEUE

def storage_stats_es(result_root : String, es_client : Elasticsearch::Client, job_content : JSON::Any)
    stats_path = "#{result_root}/stats.json"
    stats = File.open(stats_path) do |file|
        JSON.parse(file)
    end
    update_content = {"stats" => stats.as_h}

    old_content = job_content.as_h
    content = old_content.merge(update_content)

    job = JSON.parse(content.to_json)
    job_obj = Job.new(job)

    es_client.set_job_content(job_obj)
end

def consume_scheduler_queue(redis_client : Redis::Client, data_queue : String, scheduler_queue : String, es_client : Elasticsearch::Client)
    loop do
        job_id= redis_client.move_job(scheduler_queue, data_queue)
        if job_id != "0"
            # get_result_root
            job_content = es_client.not_nil!.get_job_content(job_id.to_s)
            result_root = job_content["result_root"].to_s
            job_json = JSON.parse(job_content.to_json)

            # extract_stats
            system "#{ENV["CCI_SRC"]}/sbin/result2stats #{result_root}"

            # storage_data
            storage_stats_es(result_root, es_client, job_json)

            redis_client.@client.zrem(data_queue , "#{job_id}")
        else
            sleep(1)
            next
        end
    end
end

es_client = Elasticsearch::Client.new(JOB_ES_HOST, JOB_ES_PORT)
redis_client = Redis::Client.new(redis_host, redis_port)
consume_scheduler_queue(redis_client, data_extract_queue, scheduler_extract_queue, es_client)
