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

    getter job_hash : Hash(String, JSON::Any)
    ASSIGN_KEY = %w(
      id lkp_initrd_user os os_arch
      os_dir os_version result_root
      suite tbox_group
    )
    INIT_FIELD = {
      os: "debian",
      os_arch: "aarch64",
      os_version: "sid",
      lkp_initrd_user: "latest"
    }

    def initialize(job_content : JSON::Any)
      @job_hash = job_content.as_h
      set_defaults()
    end

    macro method_missing(call)
      if ASSIGN_KEY.includes?({{ call.name.stringify }})
        @job_hash[{{ call.name.stringify }}].to_s
      else
        raise "Unassigned key or undefined method: #{{{ call.name.stringify }}}"
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

    private def set_defaults()
      append_init_field()
      set_os_dir()
      set_result_root()
      set_tbox_group()
    end

    private def append_init_field()
      INIT_FIELD.each do |k, v|
        k = k.to_s
        if !@job_hash[k]? || @job_hash[k] == nil
          @job_hash.any_merge!({k => v})
        end
      end
    end

    private def set_os_dir()
      @job_hash.any_merge!({"os_dir" => "#{os}/#{os_arch}/#{os_version}"})
    end

    private def set_result_root()
      @job_hash.any_merge!({"result_root" => "/result/#{suite}/#{id}"})
    end

    private def set_tbox_group()
      if !@job_hash["tbox_group"]?
        find = @job_hash["testbox"].to_s.match(/(.*)(\-\d{1,}$)/)
        if find != nil
          @job_hash.any_merge!({"tbox_group" => find.not_nil![1]})
        else
          @job_hash.any_merge!({"tbox_group" => @job_hash["testbox"]})
        end
      end
    end

end
