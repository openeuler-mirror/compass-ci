# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "yaml"
require "any_merge"

require "scheduler/constants.cr"
require "scheduler/jobfile_operate.cr"

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
    if testbox =~ /(.*)-\d+$/
      tbox_group = $1
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
    os:              "openeuler",
    lab:             LAB,
    os_arch:         "aarch64",
    os_version:      "20.03",
    lkp_initrd_user: "latest",
    docker_image:    "centos:7",
  }

  def initialize(job_content : JSON::Any, id)
    @hash = job_content.as_h

    # init job with "-1", or use the original job_content["id"]
    id = "-1" if "#{id}" == ""

    if initialized?
      return if @hash["id"] == "#{id}"
    end

    @hash["id"] = JSON::Any.new("#{id}")
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
    initrds_uri
    result_root
    access_key
    access_key_file
    lkp_initrd_user
    user_lkp_src
    kernel_uri
    kernel_append_root
    kernel_params
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
    hash_dup = hash.dup
    ["id", "tbox_group"].each do |key|
      if hash_dup.has_key?(key)
        unless hash_dup[key] == @hash[key]
          raise "Should not direct update #{key}, use update_#{key}"
        end
        hash_dup.delete(key)
      end
    end

    @hash.any_merge!(hash_dup)
  end

  def update(json : JSON::Any)
    update(json.as_h)
  end

  private def set_defaults
    append_init_field()
    set_user_lkp_src()
    set_os_dir()
    set_result_root()
    set_result_service()
    set_os_mount()
    set_depends_initrd()
    set_initrds_uri()
    set_kernel_uri()
    set_kernel_append_root()
    set_kernel_params()
    set_lkp_server()
    set_sshr_port()
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
    # handle by me, then keep connect to me
    self["LKP_SERVER"] = SCHED_HOST
    self["LKP_CGI_PORT"] = SCHED_PORT.to_s

    # need further uuid check (validate? exist? no need?)
    if self["SCHED_HOST"] != SCHED_HOST # remote submited job
      # ?further fix to 127.0.0.1 (from remote ssh port forwarding)
      # ?even set self["SCHED_HOST"] and self["SCHED_PORT"]

      if self["uuid"] == ""
        puts "Job's SCHED_HOST is #{self["SCHED_HOST"]}, " +
             "current scheduler IP is: #{SCHED_HOST}"
        raise "Missing uuid for remote job"
      end
    end
  end

  private def set_sshr_port
    return unless self["sshd"]?

    self["sshr_port"] = ENV["SSHR_PORT"]
    self["sshr_port_base"] = ENV["SSHR_PORT_BASE"]
    self["sshr_port_len"] = ENV["SSHR_PORT_LEN"]
  end

  private def set_os_dir
    self["os_dir"] = "#{os}/#{os_arch}/#{os_version}"
  end

  def set_result_root
    update_tbox_group_from_testbox # id must exists, need update tbox_group
    date = Time.local.to_s("%F")
    self["result_root"] = "/result/#{suite}/#{tbox_group}/#{date}/#{id}"

    # access_key has information based on "result_root"
    #  so when set result_root, we need redo set_ to update it
    set_access_key()
  end

  private def set_access_key
    self["access_key"] = "#{Random::Secure.hex(10)}-#{id}" unless @hash["access_key"]?
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
      raise "Should not use []= update #{key}, use update_#{key}"
    end
    @hash[key] = JSON::Any.new(value) if value
  end

  # defaults to the 1st value
  VALID_OS_MOUNTS = ["initramfs", "nfs", "cifs", "container"]

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

  private def initialized?
    initialized_keys = [] of String

    REQUIRED_KEYS.each do |key|
      initialized_keys << key.to_s
    end

    METHOD_KEYS.each do |key|
      initialized_keys << key.to_s
    end

    INIT_FIELD.each do |key, _value|
      initialized_keys << key.to_s
    end

    initialized_keys += ["result_service",
                         "LKP_SERVER",
                         "LKP_CGI_PORT",
                         "SCHED_HOST",
                         "SCHED_PORT"]

    initialized_keys.each do |key|
      if @hash.has_key?(key) == false
        return false
      end
    end

    return false if "#{@hash["id"]}" == ""
    return true
  end

  private def set_kernel_uri
    self["kernel_uri"] = "kernel #{OS_HTTP_PREFIX}" +
                         "#{JobHelper.service_path("#{SRV_OS}/#{os_dir}/vmlinuz")}"
  end

  private def kernel_common_params
    return "user=lkp job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job rootovl ip=dhcp ro"
  end

  private def common_initrds
    temp_initrds = [] of String

    temp_initrds << "#{INITRD_HTTP_PREFIX}" +
                    "#{JobHelper.service_path("#{SRV_INITRD}/lkp/#{lkp_initrd_user}/lkp-#{os_arch}.cgz")}"
    temp_initrds << "#{SCHED_HTTP_PREFIX}/job_initrd_tmpfs/#{id}/job.cgz"

    return temp_initrds
  end

  private def initramfs_initrds
    temp_initrds = [] of String

    osimage_dir = "#{SRV_INITRD}/osimage/#{os_dir}"
    temp_initrds << "#{INITRD_HTTP_PREFIX}" +
                    "#{JobHelper.service_path("#{osimage_dir}/current")}"
    temp_initrds << "#{INITRD_HTTP_PREFIX}" +
                    "#{JobHelper.service_path("#{osimage_dir}/run-ipconfig.cgz")}"

    temp_initrds.concat(initrd_deps.split(/ /)) unless initrd_deps.empty?
    temp_initrds.concat(initrd_pkg.split(/ /)) unless initrd_pkg.empty?

    return temp_initrds
  end

  private def nfs_cifs_initrds
    temp_initrds = [] of String

    temp_initrds << "#{OS_HTTP_PREFIX}" +
                    "#{JobHelper.service_path("#{SRV_OS}/#{os_dir}/initrd.lkp")}"

    return temp_initrds
  end

  private def get_initrds
    temp_initrds = [] of String

    if "#{os_mount}" == "initramfs"
      temp_initrds.concat(initramfs_initrds())
    elsif "#{os_mount}" == "nfs" || "#{os_mount}" == "cifs"
      temp_initrds.concat(nfs_cifs_initrds())
    end

    temp_initrds.concat(common_initrds())

    return temp_initrds
  end

  private def initrds_basename
    basenames = ""

    get_initrds().each do |initrd|
      basenames += "initrd=#{File.basename(initrd)} "
    end

    return basenames
  end

  private def set_initrds_uri
    uris = ""

    get_initrds().each do |initrd|
      uris += "initrd #{initrd}\n"
    end

    self["initrds_uri"] = uris
  end

  private def set_kernel_append_root
    os_real_path = JobHelper.service_path("#{SRV_OS}/#{os_dir}")

    fs2root = {
      "nfs"  => "root=#{OS_HTTP_HOST}:#{os_real_path} #{initrds_basename()}",
      "cifs" => "root=cifs://#{OS_HTTP_HOST}#{os_real_path}" +
                ",guest,ro,hard,vers=1.0,noacl,nouser_xattr #{initrds_basename()}",
      "initramfs" => "rdinit=/sbin/init prompt_ramdisk=0 #{initrds_basename()}",
      "container" => "",
    }

    self["kernel_append_root"] = fs2root[os_mount]
  end

  private def kernel_console
    if os_arch == "x86_64"
      return "console=ttyS0,115200 console=tty0"
    else
      return ""
    end
  end

  private def set_kernel_params
    self["kernel_params"] = " #{kernel_common_params()} #{kernel_append_root} #{kernel_console()}"
  end

  private def set_user_lkp_src
    lkp_arch_cgz = "#{SRV_INITRD}/lkp/#{lkp_initrd_user}/lkp-#{os_arch}.cgz"
    raise "The #{lkp_arch_cgz} does not exist." unless File.exists?(lkp_arch_cgz)

    self["user_lkp_src"] = Jobfile::Operate.prepare_lkp_tests(lkp_initrd_user, os_arch)
  end

  private def set_depends_initrd
    initrd_deps_arr = Array(String).new
    initrd_pkg_arr = Array(String).new

    get_depends_initrd(get_program_params(), initrd_deps_arr, initrd_pkg_arr)

    self["initrd_deps"] = initrd_deps_arr.uniq.join(" ")
    self["initrd_pkg"] = initrd_pkg_arr.uniq.join(" ")
  end

  private def get_program_params
    program_params = Hash(String, JSON::Any).new
    if @hash["monitors"]?
      program_params.merge!(@hash["monitors"].as_h)
    end

    if @hash["pp"]?
      program_params.merge!(@hash["pp"].as_h)
    end

    return program_params
  end

  private def get_depends_initrd(program_params, initrd_deps_arr, initrd_pkg_arr)
    initrd_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
    mount_type = os_mount == "cifs" ? "nfs" : os_mount.dup

    program_params.keys.each do |program|
      if program =~ /^(.*)-\d+$/
        program = $1
      end

      deps_dest_file = "#{SRV_INITRD}/deps/#{mount_type}/#{os_dir}/#{program}.cgz"
      pkg_dest_file = "#{SRV_INITRD}/pkg/#{mount_type}/#{os_dir}/#{program}.cgz"

      if File.exists?(deps_dest_file)
        initrd_deps_arr << "#{initrd_http_prefix}" + JobHelper.service_path(deps_dest_file)
      end
      if File.exists?(pkg_dest_file)
        initrd_pkg_arr << "#{initrd_http_prefix}" + JobHelper.service_path(pkg_dest_file)
      end
    end
  end

  def update_tbox_group(tbox_group)
    @hash["tbox_group"] = JSON::Any.new(tbox_group)

    # "result_root" is based on "tbox_group"
    #  so when update tbox_group, we need redo set_
    set_result_root()
  end

  def update_id(id)
    @hash["id"] = JSON::Any.new(id)

    # "result_root" => "/result/#{suite}/#{tbox_group}/#{date}/#{id}"
    # set_initrds_uri -> get_initrds -> common_initrds => ".../#{id}/job.cgz"
    #
    # "result_root, common_initrds" is associate with "id"
    #  so when update id, we need redo set_
    set_result_root()
    set_initrds_uri()
  end

  def get_uuid_tag
    uuid = self["uuid"]
    uuid != "" ? "/#{uuid}" : nil
  end
end
