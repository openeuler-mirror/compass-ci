# SPDX-License-Identifier: MulanPSL-2.0+

require "json"
require "yaml"
require "any_merge"

require "scheduler/constants.cr"

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

module JobHelper
  def self.get_tbox_group(job_content : JSON::Any)
    if job_content["tbox_group"]?
      job_content["tbox_group"]
    elsif job_content["testbox"]?
      self.match_tbox_group(job_content["testbox"].to_s)
    end
  end

  def self.match_tbox_group(testbox : String)
    tbox_group = testbox
    find = testbox.match(/(.*)(\-\d{1,}$)/)
    if find != nil
      tbox_group = find.not_nil![1]
    end
    return tbox_group
  end

  def self.service_path(path)
      temp_path = File.real_path(path)
      return temp_path.split("/srv")[-1]
  end
end

class Job

  getter hash : Hash(String, JSON::Any)

  INIT_FIELD = {
    os: "debian",
    os_arch: "aarch64",
    os_version: "sid",
    lkp_initrd_user: "latest",
    docker_image: "centos:7"
  }

  def initialize(job_content : JSON::Any)
    @hash = job_content.as_h
    check_required_keys()
    set_defaults()
  end

  METHOD_KEYS = %w(
    id
    os
    os_arch
    os_version
    os_dir
    os_mount
    arch
    suite
    tbox_group
    initrd_pkg
    initrd_deps
    result_root
    lkp_initrd_user
    kernel_append_root
    docker_image
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

  def dump_to_json_any()
    JSON.parse(dump_to_json)
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
    set_kernel_append_root()
    set_pp_initrd()
    set_lkp_server()
  end

  private def append_init_field()
    INIT_FIELD.each do |k, v|
      k = k.to_s
      if !@hash[k]? || @hash[k] == nil
        self[k] = v
      end
    end
  end

  private def set_lkp_server()
    self["LKP_SERVER"] = ENV["SCHED_HOST"]
    self["LKP_CGI_PORT"] = ENV["SCHED_PORT"]
  end

  private def set_os_dir()
    self["os_dir"] = "#{os}/#{os_arch}/#{os_version}"
  end

  private def set_result_root()
    self["result_root"] = "/result/#{suite}/#{id}"
  end

  private def set_tbox_group()
    tbox_group_name = JobHelper.get_tbox_group(JSON.parse(@hash.to_json))
    if tbox_group_name
      self["tbox_group"] = "#{tbox_group_name}"
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
        raise "Invalid os_mount: #{@hash["os_mount"]}, should be in #{VALID_OS_MOUNTS}"
      end
    else
      self["os_mount"] = VALID_OS_MOUNTS[0]
    end
  end

  REQUIRED_KEYS = %w[
    id
    suite
    testbox
  ]

  private def check_required_keys()
    REQUIRED_KEYS.each do |key|
      if !@hash[key]?
        raise "Missing required job key: '#{key}'"
      end
    end
  end

  private def set_kernel_append_root()
    os_real_path = JobHelper.service_path("#{SRV_OS}/#{os_dir}")
    lkp_real_path = JobHelper.service_path("#{SRV_OS}/#{os_dir}/initrd.lkp")
    current_real_path = JobHelper.service_path("#{SRV_INITRD}/osimage/#{os_dir}/current")
    lkp_basename = File.basename(lkp_real_path)
    current_basename = File.basename(current_real_path)
    fs2root = {
      "nfs" => "root=#{OS_HTTP_HOST}:#{os_real_path} initrd=#{lkp_basename}",
      "cifs" => "root=cifs://#{OS_HTTP_HOST}#{os_real_path}" +
          ",guest,ro,hard,vers=1.0,noacl,nouser_xattr initrd=#{lkp_basename}",
      "initramfs" => "rdinit=/sbin/init prompt_ramdisk=0 initrd=#{current_basename}"
    }
    self["kernel_append_root"] = fs2root[os_mount]
  end

  private def set_pp_initrd()
    initrd_deps_arr = Array(String).new
    initrd_pkg_arr = Array(String).new
    initrd_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
    mount_type = os_mount == "cifs" ? "nfs" : os_mount.dup
    if @hash["pp"]?
      program_params = @hash["pp"].as_h
      program_params.keys.each do |program|
        dest_file="#{mount_type}/#{os_dir}/#{program}"
        if File.exists?("#{ENV["LKP_SRC"]}/distro/depends/#{program}") &&
          File.exists?("#{SRV_INITRD}/deps/#{dest_file}.cgz")
          initrd_deps_arr << "#{initrd_http_prefix}" +
            JobHelper.service_path("#{SRV_INITRD}/deps/#{dest_file}.cgz")
        end
        if File.exists?( "#{ENV["LKP_SRC"]}/pkg/#{program}") &&
          File.exists?("#{SRV_INITRD}/pkg/#{dest_file}.cgz")
          initrd_pkg_arr << "#{initrd_http_prefix}" +
            JobHelper.service_path("#{SRV_INITRD}/pkg/#{dest_file}.cgz")
        end
      end
    end
    self["initrd_deps"] = initrd_deps_arr.join(" ")
    self["initrd_pkg"] = initrd_pkg_arr.join(" ")
  end
end
