# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "yaml"
require "any_merge"

require "scheduler/constants.cr"
require "scheduler/jobfile_operate.cr"
require "scheduler/kernel_params.cr"
require "scheduler/pp_params.cr"
require "../scheduler/elasticsearch_client"

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

    @es = Elasticsearch::Client.new
    @hash["id"] = JSON::Any.new("#{id}")
    @account_info = Hash(String, JSON::Any).new
    check_required_keys()
    check_account_info()
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
    queue
    initrd_pkg
    initrd_deps
    initrds_uri
    rootfs
    pp_params
    submit_date
    result_root
    access_key
    access_key_file
    lkp_initrd_user
    user_lkp_src
    kernel_uri
    kernel_params
    docker_image
    kernel_version
    linux_vmlinuz_path
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
    set_submit_date()
    set_pp_params()
    set_rootfs()
    set_result_root()
    set_result_service()
    set_os_mount()
    set_kernel()
    set_depends_initrd()
    set_initrds_uri()
    set_lkp_server()
    set_sshr_info()
    set_queue()
  end

  private def set_kernel
    return if os_mount == "container"

    set_kernel_version()
    set_kernel_uri()
    set_kernel_params()
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

  private def set_sshr_info
    return unless @hash["pub_key"]?

    self["sshr_port"] = ENV["SSHR_PORT"]
    self["sshr_port_base"] = ENV["SSHR_PORT_BASE"]
    self["sshr_port_len"] = ENV["SSHR_PORT_LEN"]

    return if @account_info["found"]? == false

    set_my_ssh_pubkey
  end

  private def set_my_ssh_pubkey
    pub_key = @hash["pub_key"]?.to_s
    update_account_my_pub_key(pub_key)

    @hash["my_ssh_pubkey"] = @account_info["my_ssh_pubkey"]
  end

  private def update_account_my_pub_key(pub_key)
    my_ssh_pubkey = @account_info["my_ssh_pubkey"].as_a
    return if pub_key.empty? || my_ssh_pubkey.includes?(pub_key)

    my_ssh_pubkey << JSON::Any.new(pub_key)
    @account_info["my_ssh_pubkey"] = JSON.parse(my_ssh_pubkey.to_json)
    @es.update_account(JSON.parse(@account_info.to_json), self["my_email"].to_s)
  end

  private def set_os_dir
    self["os_dir"] = "#{os}/#{os_arch}/#{os_version}"
  end

  private def set_submit_date
    self["submit_date"] = Time.local.to_s("%F")
  end

  private def set_rootfs
    self["rootfs"] = "#{os}-#{os_version}-#{os_arch}"
  end

  def set_result_root
    update_tbox_group_from_testbox # id must exists, need update tbox_group
    self["result_root"] = File.join("/result/#{suite}/#{submit_date}/#{tbox_group}/#{rootfs}", "#{pp_params}", "#{id}")

    # access_key has information based on "result_root"
    #  so when set result_root, we need redo set_ to update it
    set_access_key()
  end

  private def set_access_key
    self["access_key"] = "#{Random::Secure.hex(10)}-#{id}"
    self["access_key_file"] = File.join("/srv/", "#{result_root}", ".#{access_key}")
  end

  private def set_result_service
    self["result_service"] = "raw_upload"
  end

  private def set_queue
    return unless self["queue"].empty?

    # set default value
    self["queue"] = tbox_group
    if tbox_group.to_s.starts_with?(/(vm|dc)-/)
      self["queue"] = "#{tbox_group}.#{arch}"
    end
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
    my_email
    my_name
    my_uuid
  ]

  private def check_required_keys
    REQUIRED_KEYS.each do |key|
      if !@hash[key]?
        raise "Missing required job key: '#{key}'"
      end
    end
  end

  private def check_account_info
    error_msg = "Failed to verify the account. Please check your configuration"
    account_info = @es.get_account(self["my_email"])
    raise account_info unless account_info.is_a?(JSON::Any)

    @account_info = account_info.as_h

    raise error_msg if @account_info["found"]? == false
    raise error_msg unless self["my_name"] == @account_info["my_name"].to_s
    raise error_msg unless self["my_uuid"] == @account_info["my_uuid"]

    @hash.delete("my_uuid")
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

    initialized_keys -= ["my_uuid"]

    initialized_keys.each do |key|
      return false unless @hash.has_key?(key)
    end

    return false if "#{@hash["id"]}" == ""
    return true
  end

  private def set_kernel_version
    boot_dir = "#{SRV_OS}/#{os_dir}/boot"
    self["kernel_version"] ||= File.basename(File.real_path "#{boot_dir}/vmlinuz").gsub("vmlinuz-", "")
    self["linux_vmlinuz_path"] = File.real_path("#{boot_dir}/vmlinuz-#{kernel_version}")
    if "#{os_mount}" == "initramfs"
      self["linux_modules_initrd"] = File.real_path("#{boot_dir}/modules-#{kernel_version}.cgz")
      self["linux_headers_initrd"] = File.real_path("#{boot_dir}/headers-#{kernel_version}.cgz")
    end
  end

  private def set_kernel_uri
    self["kernel_uri"] = "kernel #{OS_HTTP_PREFIX}" +
                         JobHelper.service_path("#{linux_vmlinuz_path}")
  end

  private def common_initrds
    temp_initrds = [] of String

    temp_initrds << "#{INITRD_HTTP_PREFIX}" +
                    JobHelper.service_path("#{SRV_INITRD}/lkp/#{lkp_initrd_user}/lkp-#{os_arch}.cgz")
    temp_initrds << "#{SCHED_HTTP_PREFIX}/job_initrd_tmpfs/#{id}/job.cgz"

    return temp_initrds
  end

  private def initramfs_initrds
    temp_initrds = [] of String

    osimage_dir = "#{SRV_INITRD}/osimage/#{os_dir}"
    temp_initrds << "#{INITRD_HTTP_PREFIX}" +
                    JobHelper.service_path("#{osimage_dir}/current")
    temp_initrds << "#{INITRD_HTTP_PREFIX}" +
                    JobHelper.service_path("#{osimage_dir}/run-ipconfig.cgz")
    temp_initrds << "#{OS_HTTP_PREFIX}" +
                    JobHelper.service_path(self["linux_modules_initrd"])
    temp_initrds << "#{OS_HTTP_PREFIX}" +
                    JobHelper.service_path(self["linux_headers_initrd"])

    temp_initrds.concat(initrd_deps.split(/ /)) unless initrd_deps.empty?
    temp_initrds.concat(initrd_pkg.split(/ /)) unless initrd_pkg.empty?

    return temp_initrds
  end

  private def nfs_cifs_initrds
    temp_initrds = [] of String

    temp_initrds << "#{OS_HTTP_PREFIX}" +
                    JobHelper.service_path("#{SRV_OS}/#{os_dir}/initrd.lkp")

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
    if @hash["monitors"]? != nil
      program_params.merge!(@hash["monitors"].as_h)
    end

    if @hash["pp"]? != nil
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

      if @hash["#{program}_version"]?
        program_version = @hash["#{program}_version"]
      else
        program_version = "latest"
      end

      deps_dest_file = "#{SRV_INITRD}/deps/#{mount_type}/#{os_dir}/#{program}/#{program}.cgz"
      pkg_dest_file = "#{SRV_INITRD}/pkg/#{mount_type}/#{os_dir}/#{program}/#{program_version}.cgz"

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
