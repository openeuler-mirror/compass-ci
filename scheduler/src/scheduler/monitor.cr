require  "./resources"
require "../redis_client"
require "../elasticsearch_client"

module Scheduler
    module Monitor
        def self.update_job_parameter(job_content : Hash, env : HTTP::Server::Context, resources : Scheduler::Resources)
            redis = resources.@redis_client.not_nil!
            job_id = job_content["id"]
            if (job_id != nil)
                redis.add_job_content(job_id, job_content.to_json)
            end
        end
    end
end
