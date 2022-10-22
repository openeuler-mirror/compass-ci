# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "yaml"
require "any_merge"
require "digest"
require "base64"

require "scheduler/constants.cr"
require "scheduler/jobfile_operate.cr"
require "scheduler/kernel_params.cr"
require "scheduler/pp_params.cr"
require "scheduler/testbox_env.cr"
require "../scheduler/elasticsearch_client"
require "./json_logger"
require "./utils"

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
    testbox.split(/\.|--/)[0]
  end

  def self.service_path(path, need_exists = true)
    temp_path = need_exists ? File.real_path(path) : path
    return temp_path.split("/srv")[-1]
  end
end

class Job
  getter hash : Hash(String, JSON::Any)
  DEFAULT_FIELD = {
    lab: LAB,
  }

  DEFAULT_OS = {
    "openeuler" => {
      "os" =>              "openeuler",
      "os_arch" =>         "aarch64",
      "os_version" =>      "20.03",
      "config" =>          "config-4.19.90-2003.4.0.0036.oe1.aarch64",
    },
    "centos" => {
      "os" =>              "centos",
      "os_arch" =>         "aarch64",
      "os_version" =>      "7.6.1810",
      "config" =>          "config-4.14.0-115.el7.0.1.aarch64",
    },
    "debian" => {
      "os" =>              "debian",
      "os_arch" =>         "aarch64",
      "os_version" =>      "sid",
      "config" =>          "config-5.4.0-4-arm64",
    },
    "ubuntu" => {
      "os" =>              "ubuntu",
      "os_arch" =>         "aarch64",
      "os_version" =>      "20.04",
      "config" =>          "config-5.4.0-65-generic",
    },
    "fedora" => {
      "os" =>              "fedora",
      "os_arch" =>         "aarch64",
      "os_version" =>      "33",
      "config" =>          "config-5.8.15-301.fc33.aarch64",
    },
    "docker" => {
      "docker_image" => "centos:7"
    }
  }

  def initialize(job_content : JSON::Any, id)
    @hash = job_content.as_h
    @es = Elasticsearch::Client.new
    @account_info = Hash(String, JSON::Any).new
    @log = JSONLogger.new
  end

  METHOD_KEYS = %w(
    id
    os
    os_arch
    os_version
    os_mount
    arch
    suite
    tbox_group
    testbox
    lab
    queue
    subqueue
    initrd_pkgs
    initrd_deps
    initrds_uri
    rootfs
    submit_date
    result_root
    upload_dirs
    kernel_uri
    modules_uri
    kernel_params
    ipxe_kernel_params
    docker_image
    kernel_version
    src_lv_suffix
    boot_lv_suffix
    pv_device
    os_lv_size
    os_lv
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

  def delete(key : String)
    initialized_keys = get_initialized_keys
    if initialized_keys.includes?(key)
      raise "Should not delete #{key}"
    else
      @hash.delete(key)
    end
  end

  def submit(id = nil)
    # init job with "-1", or use the original job_content["id"]
    id = "-1" if "#{id}" == ""
    @hash["id"] = JSON::Any.new("#{id}")
    self["job_state"] = "submit"
    self["job_stage"] = "submit"

    check_required_keys()
    check_fields_format()

    account_info = @es.get_account(self["my_email"])
    Utils.check_account_info(@hash, account_info)
    @account_info = account_info.as(JSON::Any).as_h

    check_run_time()
    set_defaults()
    delete_account_info()
    @hash.merge!(testbox_env)
    checkout_max_run()
  end

  def set_defaults
    extract_user_pkg()
    set_os_mount()
    append_init_field()
    set_os_arch()
    set_docker_os()
    set_os_version()
    set_submit_date()
    set_rootfs()
    set_result_root()
    set_result_service()
    set_depends_initrd()
    set_kernel()
    set_initrds_uri()
    set_lkp_server()
    set_sshr_info()
    set_queue()
    set_subqueue()
    set_secrets()
    set_time("submit_time")
    set_params_md5
  end

  private def checkout_max_run
    return unless hash["max_run"]?

    query = {
      "size" => 1,
      "query" => {
        "term" => {
          "all_params_md5" => hash["all_params_md5"]
        }
      },
      "sort" =>  [{
        "submit_time" => { "order" => "desc", "unmapped_type" => "date" }
      }],
      "_source" => ["id", "all_params_md5"]
    }
    total, latest_job_id = @es.get_hit_total("jobs", query)

    msg = "exceeds the max_run(#{hash["max_run"]}), #{total} jobs exist, the latest job id=#{latest_job_id}"
    raise msg if total >= hash["max_run"].to_s.to_i32
  end

  def get_md5(data : Hash(String , JSON::Any))
    tmp = Hash(String, String).new
    data.each do |k, v|
      tmp[k] = v.to_s
    end
    Digest::MD5.hexdigest(tmp.to_a.sort.to_s).to_s
  end

  private def set_params_md5
    flat_pp_hash = Hash(String, JSON::Any).new
    flat_hash(hash["pp"].as_h? || flat_pp_hash, flat_pp_hash)
    hash["pp_params_md5"] = JSON::Any.new(get_md5(flat_pp_hash))

    all_params = flat_pp_hash
    COMMON_PARAMS.each do |param|
      all_params[param] = hash[param]
    end

    hash["all_params_md5"] = JSON::Any.new(get_md5(all_params))
  end

  def set_time(key)
    self[key] = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
  end

  def set_boot_elapsed_time
    return if @hash.has_key?("boot_elapsed_time")
    return unless @hash["running_time"]?

    boot_time = Time.parse(self["boot_time"], "%Y-%m-%dT%H:%M:%S", Time.local.location)
    running_time = Time.parse(self["running_time"], "%Y-%m-%dT%H:%M:%S", Time.local.location)

    self["boot_elapsed_time"] = (running_time - boot_time).total_seconds.to_i
  rescue e
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end

  private def set_os_arch
    self["os_arch"] = @hash["arch"].to_s if @hash.has_key?("arch")
  end

  private def set_docker_os
    return unless is_docker_job?

    os_info = docker_image.split(":")
    self["os"] = os_info[0]
    self["os_version"] = os_info[1]
  end

  private def set_kernel
    return if os_mount == "container"

    set_kernel_version()
    set_kernel_uri()
    set_modules_uri()
    set_kernel_params()
  end

  private def append_init_field
    DEFAULT_FIELD.each do |k, v|
      k = k.to_s
      if !@hash[k]? || @hash[k] == nil
        self[k] = v
      end
    end

    set_default_os
  end

  private def set_default_os
    os = is_docker_job? ? "docker" : self["os"]
    key = os == "" ? "openeuler" : os
    return unless DEFAULT_OS.has_key?(key)

    DEFAULT_OS[key].each do |k, v|
      if !@hash[k]? || @hash[k] == nil
        self[k] = v
      end
    end
  end

  private def extract_user_pkg
    return unless @hash.has_key?("pkg_data")

    pkg_datas = @hash["pkg_data"].as_h
    repos = pkg_datas.keys

    # no check for now, release the comment when need that.
    # check_base_tag(pkg_datas["lkp-tests"]["tag"].to_s)

    repos.each do |repo|
      repo_pkg_data = pkg_datas[repo].as_h
      store_pkg(repo_pkg_data, repo)
    end

    delete_pkg_data_content()
  end

  private def check_base_tag(user_tag)
    raise "
    \nyour lkp-tests code tag: #{user_tag} is not the latest release tag: #{BASE_TAG},
    \nyou can run the cmd \"git -C $LKP_SRC pull --ff-only\" to update your code,
    \notherwise you will can't use some new functions." unless user_tag == BASE_TAG
  end

  private def store_pkg(repo_pkg_data, repo)
    md5 = repo_pkg_data["md5"].to_s

    dest_cgz_dir = "#{SRV_UPLOAD}/#{repo}/#{md5[0, 2]}"
    FileUtils.mkdir_p(dest_cgz_dir) unless File.exists?(dest_cgz_dir)

    dest_cgz_file = "#{dest_cgz_dir}/#{md5}.cgz"

    return if File.exists? dest_cgz_file

    pkg_tag = repo_pkg_data["tag"].to_s
    pkg_content_base64 = repo_pkg_data["content"].to_s
    dest_cgz_content = Base64.decode_string(pkg_content_base64)

    File.touch(dest_cgz_file)
    File.write(dest_cgz_file, dest_cgz_content)

    check_pkg_integrity(md5, dest_cgz_file)
  end

  private def check_pkg_integrity(md5, dest_cgz_file)
    dest_cgz_md5 = Digest::MD5.hexdigest(File.read dest_cgz_file)

    raise "check pkg integrity failed." if md5 != dest_cgz_md5
  end

  private def set_lkp_server
    # handle by me, then keep connect to me
    self["LKP_SERVER"] = SCHED_HOST
    self["LKP_CGI_PORT"] = SCHED_PORT.to_s
  end

  private def set_sshr_info
    # ssh_pub_key will always be set (maybe empty) by submit,
    # if sshd is defined anywhere in the job
    return unless @hash.has_key?("ssh_pub_key")

    self["sshr_port"] = ENV["SSHR_PORT"]
    self["sshr_port_base"] = ENV["SSHR_PORT_BASE"]
    self["sshr_port_len"] = ENV["SSHR_PORT_LEN"]

    return if @account_info["found"]? == false

    set_my_ssh_pubkey
  end

  private def set_my_ssh_pubkey
    pub_key = @hash["ssh_pub_key"]?.to_s
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

  private def set_os_version
    self["os_version"] = "#{os_version}".chomp("-iso") + "-iso" if "#{self.os_mount}" == "local"
  end

  def os_dir
    return "#{os}/#{os_arch}/#{os_version}"
  end

  private def set_submit_date
    self["submit_date"] = Time.local.to_s("%F")
  end

  private def set_rootfs
    self["rootfs"] = "#{os}-#{os_version}-#{os_arch}"
  end

  def get_testbox_type
    return "vm" if self["testbox"].starts_with?("vm")
    return "dc" if self["testbox"].starts_with?("dc")
    return "physical"
  end

  def get_boot_time
    3600
  end

  def get_reboot_time
    type = get_testbox_type
    return 1200 if type == "physical"
    return 60
  end

  def get_deadline(stage, timeout=0)
    return format_add_time(timeout) unless timeout == 0

    case stage
    when "boot"
      time = get_boot_time
    when "running"
      time = (self["timeout"]? || self["runtime"]? || 3600).to_s.to_i32
      extra_time = 0 if self["timeout"]?
      extra_time ||= [time / 8, 300].max.to_i32 + Math.sqrt(time).to_i32
    when "renew"
      return @hash["renew_deadline"]?
    when "post_run"
      time = 1800
    when "manual_check"
      time = 36000
    when "finish"
      time = get_reboot_time
    else
      return nil
    end

    extra_time ||= 0
    format_add_time(time + extra_time)
  end

  def format_add_time(time)
    (Time.local + time.second).to_s("%Y-%m-%dT%H:%M:%S+0800")
  end

  def set_deadline(stage, timeout=0)
    deadline = get_deadline(stage, timeout)
    return nil unless deadline

    self["deadline"] = deadline
  end

  def renew_deadline(time)
    deadline = Time.parse(self["deadline"], "%Y-%m-%dT%H:%M:%S", Time.local.location)
    deadline = (deadline + time.to_i32.second).to_s("%Y-%m-%dT%H:%M:%S+0800")
    self["renew_deadline"] = deadline
    self["deadline"] = deadline
  end

  def set_result_root
    update_tbox_group_from_testbox # id must exists, need update tbox_group
    self["result_root"] = File.join("/result/#{suite}/#{submit_date}/#{tbox_group}/#{rootfs}", "#{sort_pp_params}", "#{id}")
    set_upload_dirs()
  end

  def get_pkg_common_dir
    tmp_style = nil
    ["cci-makepkg", "cci-depends", "build-pkg", "pkgbuild", "rpmbuild"].each do |item|
      tmp_style = @hash[item]?
      break if tmp_style
    end
    return nil unless tmp_style
    pkg_style = Hash(String, JSON::Any).new {|h, k| h[k] = JSON::Any.new(nil)}
    pkg_style.merge!(tmp_style.as_h? || Hash(String, JSON::Any).new)

    tmp_os = pkg_style["os"].as_s? || "#{os}"
    tmp_os_arch = pkg_style["os_arch"].as_s? || "#{os_arch}"
    tmp_os_version = pkg_style["os_version"].as_s? || "#{os_version}"

    mount_type = pkg_style["os_mount"].as_s? || "#{os_mount}"
    # same usage for client
    mount_type = "nfs" if mount_type == "cifs"

    common_dir = "#{mount_type}/#{tmp_os}/#{tmp_os_arch}/#{tmp_os_version}"
    common_dir = "#{tmp_os}-#{tmp_os_version}" if @hash.has_key?("rpmbuild")

    return common_dir
  end

  def get_upload_dirs_from_config
    _upload_dirs = ""
    upload_dirs_config = "#{ENV["CCI_SRC"]}/src/lib/upload_dirs_config.yaml"
    yaml_any_hash = YAML.parse(File.read(upload_dirs_config)).as_h
    yaml_any_hash.each do |k, v|
      if @hash.has_key?(k)
        _upload_dirs += ",#{v}"
      end
    end

    return _upload_dirs
  end

  def get_package_dir
    package_dir = ""
    common_dir = get_pkg_common_dir
    return package_dir unless common_dir

    if @hash["cci-makepkg"]?
      package_dir = ",/initrd/pkg/#{common_dir}/#{@hash["cci-makepkg"]["benchmark"]}"
    elsif @hash["cci-depends"]?
      package_dir = ",/initrd/deps/#{common_dir}/#{@hash["cci-depends"]["benchmark"]}"
    elsif @hash["rpmbuild"]?
      package_dir = ",/rpm/upload/#{common_dir}"
    elsif @hash["build-pkg"]? || @hash["pkgbuild"]?
      package_name = @hash["upstream_repo"].to_s.split("/")[-1]
      package_dir = ",/initrd/build-pkg/#{common_dir}/#{package_name}"
      package_dir += ",/cci/build-config" if @hash["config"]?
      if @hash["upstream_repo"].to_s =~ /^l\/linux\//
        self["config"] = DEFAULT_OS[self["os"]]["config"] unless @hash["config"]?
        package_dir += ",/kernel/#{os_arch}/#{self["config"]}/#{@hash["upstream_commit"]}"
      end
    end

    return package_dir
  end

  def set_time
    self["time"] = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
  end

  def set_upload_dirs
    self["upload_dirs"] = "#{result_root}#{get_package_dir}#{get_upload_dirs_from_config}"
  end

  private def set_result_service
    self["result_service"] = "raw_upload"
  end

  private def set_queue
    return unless self["queue"].empty?

    # set default value
    self["queue"] = tbox_group
    if tbox_group.to_s.starts_with?(/(vm|dc|vt)-/)
      self["queue"] = "#{tbox_group}.#{arch}"
    end
  end

  private def set_subqueue
    self["subqueue"] = self["my_email"] unless self["subqueue"] == "idle"
  end

  private def set_secrets
    if self["secrets"] == ""
      self["secrets"] = {"my_email" => self["my_email"]}
    else
      secrets = @hash["secrets"]?.not_nil!.as_h
      secrets.merge!({"my_email" => JSON::Any.new(self["my_email"])})
      self["secrets"] = secrets
    end
  end

  # if not assign tbox_group, set it to a match result from testbox
  #  ?if job special testbox, should we just set tbox_group=testbox
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

  def has_key?(key : String)
    @hash.has_key?(key)
  end

  def []=(key : String, value)
    if key == "id" || key == "tbox_group"
      raise "Should not use []= update #{key}, use update_#{key}"
    end
    @hash[key] = JSON.parse(value.to_json)
  end

  private def is_docker_job?
    if testbox =~ /^dc/
      return true
    else
      return false
    end
  end

  # defaults to the 1st value
  VALID_OS_MOUNTS = ["initramfs", "nfs", "cifs", "container", "local"]

  private def set_os_mount
    if is_docker_job?
      self["os_mount"] = "container"
      return
    end

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
    my_token
  ]

  private def check_required_keys
    REQUIRED_KEYS.each do |key|
      if !@hash[key]?
        error_msg = "Missing required job key: '#{key}'."
        if ["my_email", "my_name", "my_token"].includes?(key)
          error_msg += "\nPlease refer to https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/account/apply-account.md"
        end
        raise error_msg
      end
    end
  end

  private def check_fields_format
    check_rootfs_disk()
  end

  private def delete_account_info
    @hash.delete("my_uuid")
    @hash.delete("my_token")
    @hash.delete("my_email")
    @hash.delete("my_name")
  end

  private def check_run_time
    # only job.yaml for borrowing machine has the key: ssh_pub_key
    return unless @hash.has_key?("ssh_pub_key")

    # the maxmum borrowing time is limited no more than 30 days.
    # case the runtime/sleep value count beyond the limit,
    # it will throw error message and prevent the submit for borrowing machine.
    # runtime value is converted to second.
    max_run_time = 30 * 24 * 3600
    error_msg = "\nMachine borrow time(runtime/sleep) cannot exceed 30 days. Consider re-borrow.\n"

    if @hash["pp"]["sleep"].as_i?
      sleep_run_time = @hash["pp"]["sleep"]
    elsif @hash["pp"]["sleep"].as_h?
      sleep_run_time = @hash["pp"]["sleep"]["runtime"]
    else
      notice_msg = "\nPlease set runtime/sleep first for the job yaml and retry."
      raise notice_msg
    end

    raise error_msg if sleep_run_time.as_i > max_run_time
  end

  private def get_initialized_keys
    initialized_keys = [] of String

    REQUIRED_KEYS.each do |key|
      initialized_keys << key.to_s
    end

    METHOD_KEYS.each do |key|
      initialized_keys << key.to_s
    end

    DEFAULT_FIELD.each do |key, _value|
      initialized_keys << key.to_s
    end

    initialized_keys += ["os",
                         "os_arch",
                         "os_version",
                         "result_service",
                         "LKP_SERVER",
                         "LKP_CGI_PORT",
                         "SCHED_HOST",
                         "SCHED_PORT"]

    initialized_keys -= ["my_token",
                         "kernel_version",
                         "kernel_uri",
                         "modules_uri",
                         "kernel_params",
                         "ipxe_kernel_params"]
  end

  def boot_dir
    return "#{SRV_OS}/#{os_dir}/boot"
  end

  private def set_kernel_version
    self["kernel_version"] ||= File.basename(File.real_path "#{boot_dir}/vmlinuz").gsub("vmlinuz-", "")
  end

  private def set_kernel_uri
    return if @hash.has_key?("kernel_uri")
    vmlinuz_path = File.real_path("#{boot_dir}/vmlinuz-#{kernel_version}")
    self["kernel_uri"] = "#{OS_HTTP_PREFIX}" + JobHelper.service_path(vmlinuz_path)
  end

  private def set_modules_uri
    return if @hash.has_key?("modules_uri")
    return if @hash["os_mount"] == "local"

    modules_path = File.real_path("#{boot_dir}/modules-#{kernel_version}.cgz")
    self["modules_uri"] = "#{OS_HTTP_PREFIX}" + JobHelper.service_path(modules_path)
  end

  # http://172.168.131.113:8800/kernel/aarch64/config-4.19.90-2003.4.0.0036.oe1.aarch64/v5.10/vmlinuz
  def update_kernel_uri(full_kernel_uri)
    self["kernel_uri"] = full_kernel_uri
  end

  # http://172.168.131.113:8800/kernel/aarch64/config-4.19.90-2003.4.0.0036.oe1.aarch64/v5.10/modules.cgz
  def update_modules_uri(full_modules_uri)
    self["modules_uri"] = full_modules_uri
  end

  def get_common_initrds
    temp_initrds = [] of String
    # init custom_bootstrap cgz
    # if has custom_bootstrap field, just give bootstrap cgz to testbox, no need lkp-test/job cgz
    if @hash.has_key?("custom_bootstrap")
      raise "need runtime field in the job yaml." unless @hash.has_key?("runtime")

      temp_initrds << "#{INITRD_HTTP_PREFIX}" +
        JobHelper.service_path("#{SRV_INITRD}/custom_bootstrap/#{@hash["my_email"]}/bootstrap-#{os_arch}.cgz")

      return temp_initrds
    end

    # init job.cgz
    temp_initrds << "#{SCHED_HTTP_PREFIX}/job_initrd_tmpfs/#{id}/job.cgz"

    # pkg_data:
    #   lkp-tests:
    #     tag: v1.0
    #     md5: xxxx
    #     content: yyy (base64)
    raise "you should update your lkp-tests repo." unless @hash.has_key?("pkg_data")

    @hash["pkg_data"].as_h.each do |key, value|
      program = value.as_h
      temp_initrds << "#{INITRD_HTTP_PREFIX}" +
        JobHelper.service_path("#{SRV_UPLOAD}/#{key}/#{os_arch}/#{program["tag"]}.cgz")
      temp_initrds << "#{INITRD_HTTP_PREFIX}" +
        JobHelper.service_path("#{SRV_UPLOAD}/#{key}/#{program["md5"].to_s[0,2]}/#{program["md5"]}.cgz")
    end

    return temp_initrds
  end

  private def initramfs_initrds
    temp_initrds = [] of String

    osimage_dir = "#{SRV_INITRD}/osimage/#{os_dir}"
    temp_initrds << "#{INITRD_HTTP_PREFIX}" +
                    JobHelper.service_path("#{osimage_dir}/current")
    temp_initrds << "#{INITRD_HTTP_PREFIX}" +
                    JobHelper.service_path("#{osimage_dir}/run-ipconfig.cgz")

    temp = [] of String
    deps = @hash["initrd_deps"].as_a
    deps.map{ |item| temp << item.to_s }
    pkg = @hash["initrd_pkgs"].as_a
    pkg.map{ |item| temp << item.to_s }

    temp_initrds.concat(temp)
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
    elsif ["nfs", "cifs", "local"].includes? "#{os_mount}"
      temp_initrds.concat(nfs_cifs_initrds())
    end

    temp_initrds.concat(get_common_initrds())

    return temp_initrds
  end

  private def initrds_basename : Array(String)
    return os_mount == "container" ? [] of String : get_initrds.map { |initrd| "initrd=#{File.basename(initrd)}" }
  end

  private def set_initrds_uri
    initrds_uri_values = [] of JSON::Any

    get_initrds().each do |initrd|
      initrds_uri_values << JSON::Any.new("#{initrd}")
    end

    @hash["initrds_uri"] = JSON::Any.new(initrds_uri_values)
  end

  def append_initrd_uri(initrd_uri)
    if "#{os_mount}" == "initramfs"
      temp = @hash["initrds_uri"].as_a
      temp << JSON::Any.new(initrd_uri)
      self["initrds_uri"] = JSON::Any.new(temp)
    end

    temp = @hash["initrd_deps"].as_a
    temp << JSON::Any.new(initrd_uri)
    self["initrd_deps"] = temp
  end

  private def set_depends_initrd
    initrd_deps_arr = Array(String).new
    initrd_pkgs_arr = Array(String).new

    get_depends_initrd(get_program_params(), initrd_deps_arr, initrd_pkgs_arr)

    self["initrd_deps"] = initrd_deps_arr.uniq
    self["initrd_pkgs"] = initrd_pkgs_arr.uniq
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

  private def get_depends_initrd(program_params, initrd_deps_arr, initrd_pkgs_arr)
    initrd_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
    mount_type = os_mount == "cifs" ? "nfs" : os_mount.dup

    # init deps lkp.cgz
    mount_type = os_mount == "cifs" ? "nfs" : os_mount.dup
    deps_lkp_cgz = "#{SRV_INITRD}/deps/#{mount_type}/#{os_dir}/lkp/lkp.cgz"
    if File.exists?(deps_lkp_cgz)
      initrd_deps_arr << "#{initrd_http_prefix}" + JobHelper.service_path(deps_lkp_cgz)
    end

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
        initrd_pkgs_arr << "#{initrd_http_prefix}" + JobHelper.service_path(pkg_dest_file)
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

  private def check_rootfs_disk
    @hash["rootfs_disk"].as_a if @hash.has_key?("rootfs_disk")
  rescue
    raise "rootfs_disk must be in array type if you want to specify it."
  end

  def set_rootfs_disk(rootfs_disk)
    @hash["rootfs_disk"] = JSON::Any.new(rootfs_disk)
  end

  def set_crashkernel(crashkernel)
    @hash["crashkernel"] = JSON::Any.new(crashkernel)
  end

  def get_uuid_tag
    uuid = self["uuid"]
    uuid != "" ? "/#{uuid}" : nil
  end

  def delete_pkg_data_content
    return unless @hash.has_key?("pkg_data")

    new_pkg_data = Hash(String, JSON::Any).new
    pkg_datas = @hash["pkg_data"].as_h
    pkg_datas.each do |k, v|
      tmp = pkg_datas[k].as_h
      tmp.delete("content") if tmp.has_key?("content")
      new_pkg_data.merge!({k => JSON::Any.new(tmp)})
    end
    @hash["pkg_data"] = JSON::Any.new(new_pkg_data)
  end

  def delete_kernel_params
    @hash.delete("kernel_version")
    @hash.delete("kernel_uri")
    @hash.delete("modules_uri")
  end

  def delete_host_info
    @hash.delete("memory")
    @hash.delete("nr_hdd_partitions")
    @hash.delete("hdd_partitions")
    @hash.delete("ssd_partitions")
    @hash.delete("rootfs_disk")
    @hash.delete("mac_addr")
    @hash.delete("arch")
    @hash.delete("nr_node")
    @hash.delete("nr_cpu")
    @hash.delete("model_name")
    @hash.delete("ipmi_ip")
    @hash.delete("serial_number")
  end
end
