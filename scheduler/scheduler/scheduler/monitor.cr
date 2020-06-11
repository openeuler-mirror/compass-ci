require  "./resources"
require "../redis_client"
require "../elasticsearch_client"

module Scheduler
    module Monitor
        def self.update_job_parameter(job_content, env : HTTP::Server::Context, resources : Scheduler::Resources)
            resources.@redis_client.not_nil!.add_job_content(job_content)
        end

        def self.update_job_when_finished(job_id : String, resources : Scheduler::Resources)
            es = resources.@es_client.not_nil!
            redis = resources.@redis_client.not_nil!
            job_result = redis.@client.hget("sched/id2job", job_id)
            if job_result != nil
                job_result = JSON.parse(job_result.not_nil!).as_h
                job_result = job_result.merge({"id" => job_id})
                es.update("#{JOB_INDEX_TYPE}", job_result)
            end
            redis.remove_finished_job(job_id)
        end
    end
end
