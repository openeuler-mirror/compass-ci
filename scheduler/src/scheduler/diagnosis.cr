require  "./resources"

# test resource connection
# - redis
# - elasticsearch
#

module Scheduler
    module Diagnosis

        def self.test(env : HTTP::Server::Context, resources : Scheduler::Resources)
            begin
                respon_es = resources.@es_client.not_nil!.testConnect
            rescue exception
                respon_es = exception.to_s
            end
            
            begin
                respon_redis = resources.@redis_client.not_nil!.testConnect
            rescue exception
                respon_redis = exception.to_s
            end

            return "elasticsearch:\n #{respon_es}\nredis:\n #{respon_redis}\n"
        end

        def self.respon(env : HTTP::Server::Context, resources : Scheduler::Resources)
            return test(env, resources)
        end

    end
end