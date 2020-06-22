require "json"
require "yaml"

class Job

    @job_hash : Hash(String, JSON::Any)
    ASSIGN_KEY = %w(id suite os os_version)

    def initialize(job_content : JSON::Any)
        @job_hash = job_content.as_h
    end

    macro method_missing(call)
        if ASSIGN_KEY.includes?({{ call.name.stringify }})
            @job_hash[{{ call.name.stringify }}].to_s
        else
            raise "Unassigned key"
        end
    end

    def dump_to_json()
        @job_hash.to_json
    end

    def dump_to_yaml()
        @job_hash.to_yaml
    end
end
