require  "./resources"
require "../redis_client"
require "../elasticsearch_client"

module Scheduler
    module Monitor
        def self.update_job_parameter(hash : Hash, env : HTTP::Server::Context, resources : Scheduler::Resources)
            es = resources.@es_client.not_nil!
            job_id = hash["job"]
            if (job_id != nil)
                es.update("jobs/job", {hash.last_key => hash.last_value}, "#{job_id}")
            end
        end
    end
end
