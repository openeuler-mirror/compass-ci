require  "./resources"
require "../redis_client"
require "../elasticsearch_client"

module Scheduler
    module Monitor
        def self.update_job_parameter(hash : Hash, env : HTTP::Server::Context, resources : Scheduler::Resources)
            redis = resources.@redis_client.not_nil!
            job_id = hash["job_id"]
            if (job_id != nil)
                redis.add_job_content(job_id, hash.to_json)
            end
        end
    end
end
