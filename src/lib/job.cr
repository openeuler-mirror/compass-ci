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

    getter hash : Hash(String, JSON::Any)

    INIT_FIELD = {
      os: "debian",
      os_arch: "aarch64",
      os_version: "sid",
      lkp_initrd_user: "latest"
    }

    def initialize(job_content : JSON::Any)
      @hash = job_content.as_h
      set_defaults()
    end

    METHOD_KEYS = %w(
      id
      lkp_initrd_user
      os
      os_arch
      os_version
      os_dir
      os_mount
      result_root
      suite
      tbox_group
    )

    macro method_missing(call)
      if METHOD_KEYS.includes?({{ call.name.stringify }})
        @hash[{{ call.name.stringify }}].to_s
      else
        raise "Unassigned key or undefined method: #{{{ call.name.stringify }}}"
      end
    end

    def dump_to_json()
      @hash.to_json
    end

    def dump_to_yaml()
      @hash.to_yaml
    end

    def update(hash : Hash)
      @hash.any_merge!(hash)
    end

    def update(json : JSON::Any)
      @hash.any_merge!(json.as_h)
    end

    private def set_defaults()
      append_init_field()
      set_os_dir()
      set_result_root()
      set_tbox_group()
      set_os_mount()
    end

    private def append_init_field()
      INIT_FIELD.each do |k, v|
        k = k.to_s
        if !@hash[k]? || @hash[k] == nil
          self[k] = v
        end
      end
    end

    private def set_os_dir()
      self["os_dir"] = "#{os}/#{os_arch}/#{os_version}"
    end

    private def set_result_root()
      self["result_root"] = "/result/#{suite}/#{id}"
    end

    private def set_tbox_group()
      if !@hash["tbox_group"]?
        find = @hash["testbox"].to_s.match(/(.*)(\-\d{1,}$)/)
        if find != nil
          self["tbox_group"] = find.not_nil![1]
        else
          self["tbox_group"] = @hash["testbox"].to_s
        end
      end
    end

    private def []=(key : String, value : String)
      @hash[key] = JSON::Any.new(value)
    end

    # defaults to the 1st value
    VALID_OS_MOUNTS = ["nfs", "initramfs", "cifs"]
    private def set_os_mount()
      if @hash["os_mount"]?
        if !VALID_OS_MOUNTS.includes?(@hash["os_mount"].to_s)
          raise "os_mount : #{@hash["os_mount"]} is not in #{VALID_OS_MOUNTS}"
        end
      else
        self["os_mount"] = VALID_OS_MOUNTS[0]
      end
    end
end
