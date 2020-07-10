require  "./resources"
require "../redis_client"
require "../elasticsearch_client"

module Scheduler
    module Monitor
        def self.update_job_parameter(job_content, env : HTTP::Server::Context, resources : Scheduler::Resources)
            resources.@redis_client.not_nil!.add_job_content(job_content)
        end
    end
end
