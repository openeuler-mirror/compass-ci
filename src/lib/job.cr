require "json"
require "yaml"
require "any_merge"

struct JSON::Any
 def []=(key : String, value : String)
   case object = @raw
   when Hash(String, JSON::Any)
     object[key] = JSON::Any.new(value)
   else
     raise "Expect Hash for #[](String, JSON::Any), not #{object.class}"
   end
 end
end

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

    def update(hash : Hash)
      @job_hash.any_merge!(hash)
    end

    def update(json : JSON::Any)
      @job_hash.any_merge!(json.as_h)
    end
end
