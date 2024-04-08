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

  def initialize(job_content : JSON::Any, id)
    @hash = job_content.as_h
    @es = Elasticsearch::Client.new
    @account_info = Hash(String, JSON::Any).new
    @log = JSONLogger.new
    @os_info = YAML.parse(File.read("#{ENV["CCI_SRC"]}/rootfs/os.yaml")).as_h
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

  def shrink_to_etcd_json
    hh = {}
    %w(job_state job_stage job_health last_success_stage
      testbox boot_time start_time end_time close_time in_watch_queue).each do |k|
      hh[k] = @hash[k] if @hash.include? k
    end
    hh.to_json
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
    
    set_account_info()
    check_run_time()
    set_defaults()
    @hash.merge!(testbox_env)
    checkout_max_run()
  end

  def set_defaults
    extract_user_pkg()
    append_init_field()
    set_os_mount()
    set_os_arch()
    set_os_version()
    check_docker_image()
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
    set_params_md5()
  end

  def set_account_info
    account_info = @es.get_account(self["my_email"])
    Utils.check_account_info(@hash, account_info)
    @account_info = account_info.as(JSON::Any).as_h
  end

  def delete_account_info
    @hash.delete("my_uuid")
    @hash.delete("my_token")
    @hash.delete("my_email")
    @hash.delete("my_name")
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

  private def check_docker_image
    return unless is_docker_job?

    # check docker image name
    image, tag = docker_image.split(":")
    if @os_info[self.os]? and @os_info[self.os]["docker_image"]?
        known_image = @os_info[self.os]["docker_image"].as_s
        raise "Invalid docker image '#{image}' for os '#{self.os}', should be '#{known_image}'" if image != known_image
    end

    # docker tags may change over time, so no way to enforce check here
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

    unless repo_pkg_data.include? "content"
      @hash["upload_pkg_data"] ||= []
      @hash["upload_pkg_data"] << repo
    end

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
    unless @account_info.has_key?("my_ssh_pubkey")
      @account_info["my_ssh_pubkey"] = JSON::Any.new([] of JSON::Any)
    end
    my_ssh_pubkey = @account_info["my_ssh_pubkey"].as_a? || [] of JSON::Any
    return if pub_key.empty? || my_ssh_pubkey.includes?(pub_key)

    my_ssh_pubkey << JSON::Any.new(pub_key)
    @account_info["my_ssh_pubkey"] = JSON.parse(my_ssh_pubkey.to_json)
    @es.update_account(JSON.parse(@account_info.to_json), self["my_email"].to_s)
  end

  private def set_os_version
    self["os_version"] = "#{os_version}".chomp("-iso") + "-iso" if "#{self.os_mount}" == "local"
    self["osv"] = "#{os}@#{os_version}" # for easy ES search
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
        self["config"] = @os_info[self["os"]]["config"] unless @hash["config"]?
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
    os
    os_version
    my_email
    my_name
    my_token
  ]

  private def check_required_keys
    REQUIRED_KEYS.each do |key|
      if !@hash[key]?
        error_msg = "Missing required job key: '#{key}'."
        if ["my_email", "my_name", "my_token"].includes?(key)
          error_msg += "\nPlease refer to https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/user-guide/apply-account.md"
        end
        raise error_msg
      end
    end
  end

  private def check_fields_format
    check_rootfs_disk()
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
  private def get_user_uploadfiles_fields_from_config
    user_uploadfiles_fields_config = "#{ENV["CCI_SRC"]}/src/lib/user_uploadfiles_fields_config.yaml"
    yaml_any_array = YAML.parse(File.read(user_uploadfiles_fields_config)).as_a
    return yaml_any_array
  end

  private def check_config_integrity(md5, dest_config_file)
      dest_config_content_md5 = Digest::MD5.hexdigest(File.read dest_config_file)
      raise "check pkg integrity failed." if md5 != dest_config_content_md5
  end

  private def get_dest_dir(field_name)
    #
    # pkgbuild/build-pkg：$suite/pkg_name/field_name/filename
    # ss(field_name=ss.*.config*): $suite/ss.*.config*/filename
    # other:  $suite/field_name/filename
    if (field_name =~ /ss\..*\.config.*/) ||
      @hash["suite"].as_s != "build-pkg" && @hash["suite"].as_s != "pkgbuild"
      dest_dir = "#{SRV_USER_FILE_UPLOAD}/#{@hash["suite"].to_s}/#{field_name}"
    else
      _pkgbuild_repo = @hash["pkgbuild_repo"].as_s
      pkg_name = _pkgbuild_repo.chomp.split('/', remove_empty: true)[-1]
      dest_dir = "#{SRV_USER_FILE_UPLOAD}/#{@hash["suite"].as_s}/#{pkg_name}/#{field_name}"
    end
    return dest_dir
  end

  private def generate_upload_fields(field_config)
      uploaded_file_path_hash = Hash(String, String).new
      upload_fields = [] of String
      ss = Hash(String, JSON::Any).new
      #process upload file field from ss.*.config*
      ss = @hash["ss"]?.not_nil!.as_h if @hash.has_key?("ss")
      ss.each do |pkg_name, pkg_params|
        params =  pkg_params == nil ? next : pkg_params.as_h
        params.keys().each do |key|
          if key =~ /config.*/ && params[key] != nil
            field_name = "ss.#{pkg_name}.#{key}"
            filename = File.basename(params[key].to_s.chomp)
            dest_file_path = "#{SRV_USER_FILE_UPLOAD}/#{@hash["suite"].as_s}/#{field_name}/#{filename}"
            if File.exists?(dest_file_path)
                uploaded_file_path_hash[field_name] = dest_file_path
            else
              upload_fields << field_name
            end
          end
        end
      end

      #process upload file field from #{ENV["CCI_SRC"]}/src/lib/user_uploadfiles_fields_config.yaml
      field_config.each do |field_obj|
        field_hash = field_obj.as_h
        if !field_hash.has_key?("suite") && !field_hash.has_key?("field_name")
          raise "#{ENV["CCI_SRC"]}/src/lib/user_uploadfiles_fields_config.yaml content format error!! "
        end
        _suite = field_hash["suite"].as_s?
        field_name = field_hash["field_name"].as_s
        if _suite
          next if _suite != @hash["suite"].as_s || !@hash.has_key?(field_name)
          filename = File.basename(@hash[field_name].to_s.chomp)
          dest_dir = get_dest_dir(field_name)
          dest_file_path = "#{dest_dir}/#{filename}"
          if File.exists?(dest_file_path)
            uploaded_file_path_hash[field_name] = dest_file_path
          else
            upload_fields << field_name
          end
        end
      end
      return upload_fields, uploaded_file_path_hash
  end

  def process_user_files_upload
      process_upload_fields()
      #get field that can take upload file
      field_config = get_user_uploadfiles_fields_from_config()

      #get upload_fields that need upload ,such as ss.linux.config, ss.git.configxx
      #get uploaded file info, we can add it in initrds
      upload_fields, uploaded_file_path_hash = generate_upload_fields(field_config)

      if @hash["upload_pkg_data"]
        upload_fields.concat @hash["upload_pkg_data"]
      end

      # if upload_fields size > 0, need upload ,return
      return upload_fields if !upload_fields.size.zero?

      #process if found file in server
      uploaded_file_path_hash.each do |field, filepath|
        # if field not match ss.*.config*, it is a simple job
        if !(field =~ /ss\..*\.config.*/)
          # construct initrd url for upload_file
          # save initrd url in env upload_file_url, for append in PKGBUILD source=()

          initrd_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
          upload_file_initrd = "#{initrd_http_prefix}#{JobHelper.service_path(filepath, true)}"
          @hash["upload_file_url"] = JSON::Any.new(upload_file_initrd)
        end
      end
  end

  private def process_upload_fields
      return unless @hash.has_key?("upload_fields")
      upload_fields = @hash["upload_fields"].not_nil!.as_a
      # upload_fields:
      #   md5: xxx
      #   field_name: ss.xx.config* or pkgbuild config
      #   filename: basename of file
      #   content: file content
      save_dirs = [] of String
      upload_fields.each do |upload_item|
          save_dirs << store_upload_file(upload_item.as_h)
      end
      reset_upload_field(upload_fields, save_dirs)
  end

  private def store_upload_file(to_upload)
      md5 = to_upload["md5"].to_s
      field_name = to_upload["field_name"].to_s
      file_name = to_upload["file_name"].to_s
      dest_dir = get_dest_dir(field_name)
      FileUtils.mkdir_p(dest_dir) unless File.exists?(dest_dir)
      dest_file = "#{dest_dir}/#{file_name}"
      #if file exist in server, check md5
      if File.exists?(dest_file)
          return dest_file
      end
      #save file
      content_base64 = to_upload["content"].to_s
      dest_content = Base64.decode_string(content_base64)
      File.touch(dest_file)
      File.write(dest_file, dest_content)
      # verify save
      check_config_integrity(md5, dest_file)
      return dest_file
  end

  private def reset_upload_field(upload_fields, save_dirs)
      new_upload_fields_data = [] of JSON::Any
      # iter every upload_field, remove content, add save_dir
      upload_fields.each_with_index do |item, index|
          tmp = item.as_h
          tmp["save_dir"] = JSON::Any.new(save_dirs[index])
          tmp.delete("content") if tmp.has_key?("content")
          new_upload_fields_data << JSON::Any.new(tmp)
      end
      @hash["upload_fields"] = JSON::Any.new(new_upload_fields_data)
  end
end
