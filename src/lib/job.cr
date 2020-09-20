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
    os:              "debian",
    lab:             LAB,
    os_arch:         "aarch64",
    os_version:      "sid",
    lkp_initrd_user: "latest",
    docker_image:    "centos:7",
  }

  def initialize(job_content : JSON::Any, id)
    @hash = job_content.as_h

    # init job with "-1", or use the original job_content["id"]
    if "#{id}" == ""
      @hash["id"] = JSON::Any.new("-1")
    end

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
    testbox
    lab
    initrd_pkg
    initrd_deps
    result_root
    access_key
    access_key_file
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

  def dump_to_json
    @hash.to_json
  end

  def dump_to_yaml
    @hash.to_yaml
  end

  def dump_to_json_any
    JSON.parse(dump_to_json)
  end

  def update(hash : Hash)
    if hash.has_key?("id")
      hash.delete("id")
      puts "Should not direct update id, use update_id, ignore this"
    end
    if hash.has_key?("tbox_group")
      raise "Should not direct update tbox_group, use update_tbox_group"
    end

    @hash.any_merge!(hash)
  end

  def update(json : JSON::Any)
    update(json.as_h)
  end

  private def set_defaults
    append_init_field()
    set_os_dir()
    set_result_root()
    set_result_service()
    set_access_key()
    set_os_mount()
    set_kernel_append_root()
    set_pp_initrd()
    set_lkp_server()
  end

  private def append_init_field
    INIT_FIELD.each do |k, v|
      k = k.to_s
      if !@hash[k]? || @hash[k] == nil
        self[k] = v
      end
    end
  end

  private def set_lkp_server
    if self["SCHED_HOST"] != SCHED_HOST   # remote submited job
      # ?further fix to 127.0.0.1 (from remote ssh port forwarding)
      # ?even set self["SCHED_HOST"] and self["SCHED_PORT"]

      self["LKP_SERVER"] = SCHED_HOST
      self["LKP_CGI_PORT"] = SCHED_PORT.to_s
    end
  end

  private def set_os_dir
    self["os_dir"] = "#{os}/#{os_arch}/#{os_version}"
  end

  private def set_result_root
    update_tbox_group_from_testbox # id must exists, need update tbox_group
    date = Time.local.to_s("%F")
    self["result_root"] = "/result/#{suite}/#{tbox_group}/#{date}/#{id}"
  end

  private def set_access_key
    self["access_key"] = "#{Random::Secure.hex(10)}" unless @hash["access_key"]?
    self["access_key_file"] = File.join("/srv/", "#{result_root}", ".#{access_key}")
  end

  private def set_result_service
    self["result_service"] = "raw_upload"
  end

  # if not assign tbox_group, set it to a match result from testbox
  #  ?if job special testbox, should we just set tbox_group=textbox
  private def update_tbox_group_from_testbox
    if self["tbox_group"] == ""
      @hash["tbox_group"] = JSON::Any.new(JobHelper.match_tbox_group(testbox))
    end
  end

  def [](key : String) : String
    "#{@hash[key]?}"
  end

  def []?(key : String)
    @hash.[key]?
  end

  def []=(key : String, value : String | Nil)
    if key == "id" || key == "tbox_group"
      raise "Should not []= id and tbox_group, use update_#{key}"
    end
    @hash[key] = JSON::Any.new(value) if value
  end

  # defaults to the 1st value
  VALID_OS_MOUNTS = ["nfs", "initramfs", "cifs"]

  private def set_os_mount
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

  private def check_required_keys
    REQUIRED_KEYS.each do |key|
      if !@hash[key]?
        raise "Missing required job key: '#{key}'"
      end
    end
  end

  private def set_kernel_append_root
    os_real_path = JobHelper.service_path("#{SRV_OS}/#{os_dir}")
    lkp_real_path = JobHelper.service_path("#{SRV_OS}/#{os_dir}/initrd.lkp")
    lkp_basename = File.basename(lkp_real_path)

    current_basename = ""
    if "#{os_mount}" == "initramfs"
      current_real_path = JobHelper.service_path("#{SRV_INITRD}/osimage/#{os_dir}/current")
      current_basename = File.basename(current_real_path)
    end

    fs2root = {
      "nfs"  => "root=#{OS_HTTP_HOST}:#{os_real_path} initrd=#{lkp_basename}",
      "cifs" => "root=cifs://#{OS_HTTP_HOST}#{os_real_path}" +
                ",guest,ro,hard,vers=1.0,noacl,nouser_xattr initrd=#{lkp_basename}",
      "initramfs" => "rdinit=/sbin/init prompt_ramdisk=0 initrd=#{current_basename}",
    }
    self["kernel_append_root"] = fs2root[os_mount]
  end

  private def set_pp_initrd
    initrd_deps_arr = Array(String).new
    initrd_pkg_arr = Array(String).new
    initrd_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
    mount_type = os_mount == "cifs" ? "nfs" : os_mount.dup
    if @hash["pp"]?
      program_params = @hash["pp"].as_h
      program_params.keys.each do |program|
        dest_file = "#{mount_type}/#{os_dir}/#{program}"
        if File.exists?("#{ENV["LKP_SRC"]}/distro/depends/#{program}") &&
           File.exists?("#{SRV_INITRD}/deps/#{dest_file}.cgz")
          initrd_deps_arr << "#{initrd_http_prefix}" +
                             JobHelper.service_path("#{SRV_INITRD}/deps/#{dest_file}.cgz")
        end
        if File.exists?("#{ENV["LKP_SRC"]}/pkg/#{program}") &&
           File.exists?("#{SRV_INITRD}/pkg/#{dest_file}.cgz")
          initrd_pkg_arr << "#{initrd_http_prefix}" +
                            JobHelper.service_path("#{SRV_INITRD}/pkg/#{dest_file}.cgz")
        end
      end
    end
    self["initrd_deps"] = initrd_deps_arr.join(" ")
    self["initrd_pkg"] = initrd_pkg_arr.join(" ")
  end

  def update_tbox_group(tbox_group)
    @hash["tbox_group"] = JSON::Any.new(tbox_group)
    set_result_root()
  end

  def update_id(id)
    @hash["id"] = JSON::Any.new(id)
    set_result_root()
  end
end
