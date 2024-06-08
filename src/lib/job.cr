# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "yaml"
require "set"
require "any_merge"
require "digest"
require "base64"

class JobHash
end

require "scheduler/constants.cr"
require "scheduler/jobfile_operate.cr"
require "scheduler/kernel_params.cr"
require "scheduler/pp_params.cr"
require "../scheduler/elasticsearch_client"
require "./utils"
require "./unit"

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

struct YAML::Any
  def to_s : String
    self.as_s
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

class Str2AnyHash < Hash(String, JSON::Any)
  def []=(k : String, v : String)
    self[k] = JSON::Any.new(v)
  end

  def dup
    hash = Str2AnyHash.new
    hash.initialize_dup(self)
    hash
  end
end

class HashArray < Hash(String, Array(String))
  def dup
    hash = HashArray.new
    hash.initialize_dup(self)
    hash
  end
end

class HashH < Hash(String, String)
end

class HashHH < Hash(String, Hash(String, String) | Nil)
  def dup
    hash = HashHH.new
    hash.initialize_dup(self)
    hash
  end
end

class HashHHH < Hash(String, HashHH)
  def dup
    hash = HashHHH.new
    hash.initialize_dup(self)
    hash
  end
end

def add2array(array : HashArray, k : String,  v : JSON::Any) : Bool
  if v.raw.is_a? Nil
    # comment out to filter out empty field, e.g. k="initrd_deps", v=nil
    # array[k] ||= nil
    return true
  elsif v.raw.is_a? Array
    array[k] ||= Array(String).new
    v.as_a.each { |v| array[k].as(Array) << v.to_s }
    return true
  else
    return false
  end
end

def add2hh(hh : HashHH, k : String, v : JSON::Any)
  if v.raw.is_a? Nil
    # this will keep
    #   pp.redis: nil
    #   monitors.vmstat: nil
    hh[k] ||= nil
    return true
  elsif v.raw.is_a? Hash
    h = (hh[k] ||= HashH.new)
    v.as_h.each do |kk, vv|
      if vv.raw.is_a? Nil
        # will convert boot_params.quiet= to boot_params.quiet=""
        h[kk] ||= ""
      elsif vv.raw.is_a? Array
        h[kk] = vv.as_a.map { |vvv| vvv.to_s }.join("\n")
      else
        h[kk] = vv.to_s
      end
    end
    return true
  else
    return false
  end
end

class JobHash

  getter hash_plain : Hash(String, String)
  getter hash_array : HashArray
  getter hash_hh : HashHH
  getter hash_hhh : HashHHH
  getter hash_any : Str2AnyHash

  PLAIN_SET = Set(String).new PLAIN_KEYS
  ARRAY_SET = Set(String).new ARRAY_KEYS
  HH_SET    = Set(String).new HH_KEYS
  HHH_SET   = Set(String).new HHH_KEYS

  def initialize(job_content = nil)
    @hash_any   = Str2AnyHash.new
    @hash_plain = Hash(String, String).new
    @hash_array = HashArray.new
    @hash_hh    = HashHH.new
    @hash_hhh   = HashHHH.new

    import2hash(job_content)
  end

  def initialize(ajob : JobHash)
    @hash_any   = ajob.hash_any.dup
    @hash_plain = ajob.hash_plain.dup
    @hash_array = ajob.hash_array.dup
    @hash_hh    = ajob.hash_hh.dup
    @hash_hhh   = ajob.hash_hhh.dup
  end

  # this mimics any_merge for the known types
  def import2hash(job_content : Hash(String, String) | Hash(String, JSON::Any) | Nil)
    return unless job_content

    job_content.each do |k, v|
      if v.is_a? String || v.raw.is_a? String
        if PLAIN_SET.includes? k
          @hash_plain[k] = v.to_s
        else
          raise "invalid type, expect array: Job[#{k}] = #{v}" if ARRAY_SET.includes? k
          raise "invalid type, expect hash: Job[#{k}] = #{v}" if HH_SET.includes? k
          raise "invalid type, expect hash of hash: Job[#{k}] = #{v}" if HHH_SET.includes? k
          @hash_any[k] = v
        end
      elsif PLAIN_SET.includes? k
        @hash_plain[k] = v.to_s
      elsif ARRAY_SET.includes? k
        add2array(@hash_array, k, v) || raise "invalid type, expect array: Job[#{k}] = #{v}"
      elsif HH_SET.includes? k
        # will keep: k="boot_params", v={quiet: nil} and convert nil to ""
        add2hh(@hash_hh, k, v) || raise "invalid type, expect hash: Job[#{k}] = #{v}"
      elsif HHH_SET.includes? k
        if v.raw.is_a? Nil
          # empty top level field will be auto filtered out, e.g. k="pp", v=nil
          next
        elsif v.raw.is_a? Hash
          hh = (@hash_hhh[k] ||= HashHH.new)
          v.as_h.each do |kk, vv|
            # will keep: k.kk="pp.redis", vv=nil
            # will keep: k.kk="pp.redis", vv={nr_threads: nil}, converting nil to "", though meaningless
            kk = kk.to_s
            add2hh(hh, kk, vv) || raise "invalid type, expect hash: Job[#{k}.#{kk}] = #{vv}"
          end
        else
          raise "invalid type, expect hash of hash: Job[#{k}] = #{v}"
        end
      elsif !@hash_any.includes?(k)
        @hash_any[k] = v
      elsif v.as_h?
        @hash_any.any_merge!(v.as_h)
      elsif v.as_a?
        @hash_any[k].as_a.concat(v.as_a)
      else
        @hash_any[k] = v
      end
    end
  end

  def merge!(other_job : JobHash)
    @hash_plain.merge!(other_job.hash_plain)
    @hash_any.any_merge!(other_job.hash_any)

    other_job.hash_array.each do |k, v|
      @hash_array[k] ||= Array(String).new
      v.each { |vv| @hash_array[k] << vv }
    end

    other_job.hash_hh.each do |k, v|
      if v
        h = (@hash_hh[k] ||= HashH.new)
        v.each { |kk, vv| h[kk] = vv unless vv.nil? || vv.empty? }
      else
        @hash_hh[k] ||= nil
      end
    end

    other_job.hash_hhh.each do |k, v|
      @hash_hhh[k] ||= HashHH.new
      v.each do |kk, vv|
        if vv
          h = (@hash_hhh[k][kk] ||= HashH.new)
          vv.each { |kkk, vvv| h[kkk] = vvv unless vv.nil? || vv.empty? }
        else
          @hash_hhh[k][kk] ||= nil
        end
      end
    end
  end

  def merge2hash_all
    hash_all = @hash_any.dup
    @hash_plain.each { |k, v| hash_all[k] = JSON::Any.new(v) }
    @hash_array.each do |k, v|
      hash_all[k] ||= JSON::Any.new([] of JSON::Any)
      hash_all[k].as_a.concat(v.map {|vv| JSON::Any.new(vv)})
    end
    @hash_hh.each do |k, v|
      hash_all[k] ||= JSON::Any.new({} of String => JSON::Any)
      if v
        hash_all[k].as_h.any_merge!(v)
      else
        hash_all[k] = JSON::Any.new(nil)
      end
    end
    @hash_hhh.each do |k, v|
      hash_all[k] ||= JSON::Any.new({} of String => JSON::Any)
      v.each do |kk, vv| # kk="redis", vv=nil or Hash
        hash_all[k].as_h[kk] ||= JSON::Any.new({} of String => JSON::Any)
        if vv
          hash_all[k][kk].as_h.any_merge!(vv)
        else
          hash_all[k].as_h[kk] = JSON::Any.new(nil)
        end
      end
    end
    hash_all
  end

  DEFAULT_FIELD = {
    lab: LAB,
  }

  PLAIN_KEYS = %w(
    id
    job_id
    group_id
    submit_id

    suite
    category

    os
    os_arch
    os_version
    os_variant
    os_mount
    osv

    lab
    arch
    tbox_group
    testbox
    cluster
    queue
    subqueue

    rootfs
    docker_image

    pp_params_md5
    all_params_md5

    nr_run
    max_run

    submit_date
    result_root
    result_service
    upload_dirs
    lkp_initrd_user

    kernel_uri
    ipxe_kernel_params
    kernel_version
    kernel_custom_params

    os_lv
    os_lv_size
    src_lv_suffix
    boot_lv_suffix
    pv_device

    node_roles

    loadavg
    job_state
    job_stage
    job_health
    last_success_stage

    time
    submit_time
    boot_time
    running_time
    post_run_time
    finish_time

    start_time
    end_time

    boot_seconds
    run_seconds

    in_watch_queue

    my_account
    my_email
    my_name
    my_token

    ssh_pub_key
    deadline
    renew_deadline
    custom_bootstrap

    runtime
    timeout

    config
    commit
    commit_date
    base_commit
    upstream_repo
    upstream_commit
    upstream_url
    upstream_dir
    pkgbuild_repo
    pkgbuild_source

    os_project
    build_type
    build_id
    snapshot_id
    package
    upload_image_dir
    emsx
    nickname
    host_machine
    tbox_type
    branch
    job_origin
    workflow_exec_id
    matrix
    custom_ipxe
    pr_merge_reference_name

    local_mount_repo_name
    local_mount_repo_addr
    local_mount_repo_priority
    bootstrap_mount_repo_name
    bootstrap_mount_repo_addr
    bootstrap_mount_repo_priority
    mount_repo_name
    mount_repo_addr
    mount_repo_priority
    external_mount_repo_name
    external_mount_repo_addr
    external_mount_repo_priority

    is_store
    crystal_ip

    memory_minimum
    max_duration

    spec_file_name
    use_remote_tbox
    weight

    direct_macs
    direct_ips
    nr_nic
  )

  ARRAY_KEYS = %w(
    my_ssh_pubkey
    initrds_uri
    modules_uri
    initrd_deps
    initrd_pkgs
    kernel_params
    added_by

    errid
    error_ids
  )

  # These hw.* are string arrays, so will be joined by "\n"
  # - hw.hdd_partitions
  # - hw.ssd_partitions
  # - hw.rootfs_disk
  HH_KEYS = %w(
    secrets
    services
    install_os_packages
    boot_params
    on_fail
    waited
    hw
    vt
  )

  # ss = software stack, with build time options
  # pp = program.param, runtime params will impact results
  # (config options won't impact results shall start with '_')
  HHH_KEYS = %w(
    pp
    ss
    monitors
    pkg_data
    upload_fields
  )

  # stats/result are Hash(String, Number|String), so cannot fit in HH_KEYS
  ANY_KEYS = %w(
    cluster_spec

    job2sh

    crashkernel

    wait

    stats
    result
  )

  {% for name in PLAIN_KEYS %}
    def {{name.id}};              @hash_plain[{{name}}];      end
    def {{(name + "?").id}};      @hash_plain[{{name}}]?;     end
    def {{(name + "=").id}}(v);   @hash_plain[{{name}}] = v;  end
  {% end %}

  {% for name in ARRAY_KEYS %}
    def {{name.id}};              @hash_array[{{name}}];      end
    def {{(name + "?").id}};      @hash_array[{{name}}]?;     end
    def {{(name + "=").id}}(v);   @hash_array[{{name}}] = v;  end
  {% end %}

  {% for name in HH_KEYS %}
    def {{name.id}};              @hash_hh[{{name}}];       end
    def {{(name + "?").id}};      @hash_hh[{{name}}]?;      end
    def {{(name + "=").id}}(v);   @hash_hh[{{name}}] = v;   end
  {% end %}

  {% for name in HHH_KEYS %}
    def {{name.id}};              @hash_hhh[{{name}}];      end
    def {{(name + "?").id}};      @hash_hhh[{{name}}]?;     end
    def {{(name + "=").id}}(v);   @hash_hhh[{{name}}] = v;  end
  {% end %}

  {% for name in ANY_KEYS %}
    def {{name.id}};              @hash_any[{{name}}];      end
    def {{(name + "?").id}};      @hash_any[{{name}}]?;     end
    def {{(name + "=").id}}(v);   @hash_any[{{name}}] = v;  end
  {% end %}

  def pp(program : String, option : String) : String|Nil
    return nil unless @hash_hhh["pp"]?
    return nil unless @hash_hhh["pp"][program]?
    return @hash_hhh["pp"][program].as(Hash)[option]?
  end

  def assert_key_in(key : String, vals : Set(String))
      raise "invalid key #{key}" unless vals.includes? key
  end

  def shrink_to_etcd_fields
    h = Hash(String, String).new
    %w(job_stage job_health last_success_stage
      testbox deadline time boot_time in_watch_queue).each do |k|
      assert_key_in(k, PLAIN_SET)
      h[k] = @hash_plain[k] if @hash_plain.has_key? k
    end
    h
  end

  def to_json
    merge2hash_all.to_json
  end

  def to_yaml
    merge2hash_all.to_yaml
  end

  def to_json_any
    JSON.parse(self.to_json)
  end

  def update(hash : Hash)
    hash_dup = hash.dup

    # protect static keys
    ["id", "tbox_group"].each do |key|
      if hash_dup.has_key?(key)
        unless hash_dup[key] == @hash_plain[key]
          raise "Should not direct update #{key}, use update_#{key}"
        end
        hash_dup.delete(key)
      end
    end

    import2hash(hash_dup)
  end

  def put_if_not_absent(k : String, v : String)
    @hash_plain[k] = v unless @hash_plain[k]?
  end

  def update(json : JSON::Any)
    update(json.as_h)
  end

  def force_delete(key : String)
    @hash_plain.delete(key) ||
    @hash_array.delete(key) ||
    @hash_hh.delete(key) ||
    @hash_hhh.delete(key) ||
    @hash_any.delete(key)
  end

  def delete(key : String)
    initialized_keys = get_initialized_keys
    if initialized_keys.includes?(key)
      raise "Should not delete #{key}"
    else
      force_delete key
    end
  end

  def [](key : String) : String
    assert_key_in(key, PLAIN_SET)
    "#{@hash_plain[key]?}"
  end

  def []?(key : String)
    assert_key_in(key, PLAIN_SET)
    @hash_plain.[key]?
  end

  def has_key?(key : String)
    assert_key_in(key, PLAIN_SET)
    @hash_plain.has_key?(key)
  end

  def []=(key : String, value : String)
    if key == "id" || key == "tbox_group"
      raise "Should not use []= update #{key}, use update_#{key}"
    end
    assert_key_in(key, PLAIN_SET)
    @hash_plain[key] = value
  end

  # subset of PLAIN_KEYS
  MANTI_STRING_ATTRS = %w(
    suite
    category

    os
    os_version
    os_arch

    osv
    os_mount
    rootfs

    lab
    tbox_group
    testbox

    pp_params_md5
    all_params_md5

    submit_date

    queue
    subqueue

    job_stage
    job_health

    my_account
    my_name
  )

  MANTI_INTEGER_ATTRS = %w(
    id
    submit_id
    boot_seconds
    run_seconds
  )

  # subset of PLAIN_KEYS
  MANTI_TIMESTAMP_ATTRS = %w(
    submit_time
    boot_time
    finish_time
    time
  )

  # dynamic keys to merge into the json attribute
  MANTI_JSON_KEYS = %w(
    group_id

    monitors

    kernel_version
    kernel_params

    docker_image

    cluster

    last_success_stage

    error_ids
  )

  # these keys will be merged into the full-text-search only attribute
  # Avoid costly words that differ in every job!
  MANTI_FULL_TEXT_KEYS = %w(
  )

  # All Job keys will be classified and stored in either one of:
  # - MANTI_STRING_ATTRS:     1:1 to fixed attributes, type string
  # - MANTI_INTEGER_ATTRS:    1:1 to fixed attributes, type integer(xxx_seconds) or big integer(submit_id)
  # - MANTI_TIMESTAMP_ATTRS:  1:1 to fixed attributes, type timestamp
  # - MANTI_JSON_KEYS:        merge into fixed attribute, name 'jj', type json
  # - pp/ss/hw:               standalone json fields
  # - errid/stats:            standalone indexed/stored string fields
  # - mutable variables:      merge into in mutable_vars
  # - all other keys:         merge into fixed attribute, name 'other_data', type string, not indexed
  #
  # Also collect searchable values into attribute name 'full_text_words', type text, not stored
  # - MANTI_FULL_TEXT_KEYS
  def to_manticore
    mjob = Str2AnyHash.new
    xjob = JobHash.new(self)

    MANTI_STRING_ATTRS.each do |k|
      assert_key_in(k, PLAIN_SET)
      next unless xjob.hash_plain.has_key? k

      mjob[k] = JSON::Any.new(xjob.hash_plain.delete k)
    end

    MANTI_INTEGER_ATTRS.each do |k|
      assert_key_in(k, PLAIN_SET)
      next unless xjob.hash_plain.has_key? k

      v = xjob.hash_plain.delete k
      next unless v

      case k
      when "id"
        mjob[k] = JSON::Any.new(v.split(".").last.to_i64)
      when "submit_id"
        mjob[k] = JSON::Any.new(v.to_i64)
      else
        mjob[k] = JSON::Any.new(v.to_i)
      end
    end

    MANTI_TIMESTAMP_ATTRS.each do |k|
      assert_key_in(k, PLAIN_SET)
      next unless xjob.hash_plain.has_key? k

      v = xjob.hash_plain.delete k
      next unless v

      # convert old format like "submit_time": "2024-04-27T20:14:59+0800",
      v = Time.parse(v, "%Y-%m-%dT%H:%M:%S%z", Time.local.location).to_unix_ms if v.includes? "-"
      mjob[k] = JSON::Any.new(v.to_i64)
    end

    mjob["errid"] = xjob.hash_array.delete("errid").as(Array).join(" ") if xjob.errid?

    # the below all deals with JSON::Any
    hash_all = xjob.merge2hash_all

    jj = Str2AnyHash.new
    {% for name in MANTI_JSON_KEYS %}
      if v = hash_all.delete {{name}}
        jj[{{name}}] = v
      end
    {% end %}
    mjob["jj"] = JSON::Any.new jj.as(Hash)

    {% for name in %w[hw pp ss] %}
      if v = hash_all.delete {{name}}
        mjob[{{name}}] = v
      end
    {% end %}

    mjob["stats"] = hash_all.delete("stats").to_json if xjob.stats?

    mjob["other_data"] = hash_all.to_json   # convert to a string

    mjob
  end

end

class Job < JobHash

  def initialize(job_content, id : String|Nil)
    super(job_content)
    @hash_plain["id"] = id unless id.nil?

    @es = Elasticsearch::Client.new
    @account_info = JobHash.new(Hash(String, JSON::Any).new)
    @upload_pkg_data = Array(String).new

    @is_remote = nil
  end

  def submit(id = "-1")
    # init job with "-1", or use the original job.id
    self.id = id
    self.job_state = "submit"
    self.job_stage = "submit"

    #self.merge! Utils.get_service_env()
    #self.merge! Utils.get_testbox_env(@is_remote)

    #self.emsx ||= "ems1"
    self.emsx = "ems1" unless @hash_plain.has_key?("emsx")
    self.emsx = self.emsx.downcase
    # XXX move into ["services"] subkey?
    if IS_CLUSTER
      @hash_any.merge!(Utils.testbox_env_k8s(flag="local", emsx=self["emsx"]))
    else
      self.merge! Utils.set_testbox_env(flag="local")
    end

    check_required_keys()
    check_fields_format()

    set_account_info()
    check_run_time()
    set_defaults()
    delete_account_info()
    checkout_max_run()
  end

  def set_http_prefix
    self["HTTP_PREFIX"] = ENV["LKP_HTTP_PREFIX"]
  end

  def set_remote_testbox_env
    @is_remote = true
  end

  def set_remote_mount_repo
    lmra = ""
    lmrn = ""
    lmrp = ""
    lmraa = [] of String
    bmraa = [] of String

    if self.local_mount_repo_addr?
      lmrn = self.local_mount_repo_name
      lmra = self.local_mount_repo_addr
      lmrp = self.local_mount_repo_priority

      lmra.split().each do |url|
        lmraa << url.gsub(/http:\/\/\d+\.\d+\.\d+\.\d+:\d+/, "#{ENV["REMOTE_REPO_PREFIX"]}/#{self.emsx}")
      end

      if @is_remote
        lmra = lmraa.join(" ")
      end
    end

    bmrn = ""
    bmra = ""
    bmrp = ""

    if self.bootstrap_mount_repo_addr?
      bmrn = self.bootstrap_mount_repo_name
      bmra = self.bootstrap_mount_repo_addr
      bmrp = self.bootstrap_mount_repo_priority

      bmra.split().each do |url|
        tmp = url.gsub(LOCAL_DAILYBUILD, REMOTE_DAILYBUILD)
        tmp = tmp.gsub(/http:\/\/192\.168\.\d+\.\d+:\d+/, "#{ENV["REMOTE_REPO_PREFIX"]}/#{self.emsx}")
        bmraa << tmp
      end

      if @is_remote
        bmra = bmraa.join(" ")
      end
    end

    mrn = lmrn + " " + bmrn
    mra = lmra + " " + bmra
    mrp = lmrp + " " + bmrp

    self.mount_repo_name = mrn.strip
    self.mount_repo_addr = mra.strip
    self.mount_repo_priority = mrp.strip

    lmra = lmraa.join(" ")
    bmra = bmraa.join(" ")
    mra = lmra + " " + bmra

    self.external_mount_repo_name = mrn.strip
    self.external_mount_repo_addr = mra.strip
    self.external_mount_repo_priority = mrp.strip
  end

  def set_defaults
    extract_user_pkg()
    append_init_field()
    set_os_mount()
    set_os_arch()
    set_os_version()
    check_docker_image()
    set_tbox_type()
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
    set_memory_minimum()
  end

  def set_account_info
    account_info = @es.get_account(self.my_email)
    Utils.check_account_info(@hash_plain, account_info)
    @account_info = JobHash.new(account_info.as_h)
  end

  def delete_account_info
    @hash_plain.delete("my_uuid")
    @hash_plain.delete("my_token")
    @hash_plain.delete("my_email")
    @hash_plain.delete("my_name")
  end

  private def checkout_max_run
    return unless self.max_run?

    query = {
      "size" => 1,
      "query" => {
        "term" => {
          "all_params_md5" => self.all_params_md5
        }
      },
      "sort" =>  [{
        "submit_time" => { "order" => "desc", "unmapped_type" => "date" }
      }],
      "_source" => ["id", "all_params_md5"]
    }
    total, latest_job_id = @es.get_hit_total("jobs", query)

    msg = "exceeds the max_run(#{self.max_run}), #{total} jobs exist, the latest job id=#{latest_job_id}"
    raise msg if total >= self.max_run.to_s.to_i32
  end

  def get_md5(data : Hash(String , String))
    Digest::MD5.hexdigest(data.to_a.sort.to_s).to_s
  end

  private def set_params_md5

    flat_pp_hash = Hash(String, String).new
    if @hash_hhh["pp"]?
        flat_pp_hash = flat_hh(@hash_hhh["pp"])
        self.pp_params_md5 = get_md5(flat_pp_hash)
    end

    all_params = flat_pp_hash
    COMMON_PARAMS.each do |param|
      all_params[param] = @hash_plain[param]
    end

    self.all_params_md5 = get_md5(all_params)
  end

  def set_boot_elapsed_time
    return if @hash_plain.has_key?("boot_seconds")
    return unless self.running_time?

    boot_time = Time.parse(self.boot_time, "%Y-%m-%dT%H:%M:%S", Time.local.location)
    running_time = Time.parse(self.running_time, "%Y-%m-%dT%H:%M:%S", Time.local.location)

    self.boot_seconds = (running_time - boot_time).to_s
  end

  # defaults to the 1st value
  VALID_OS_MOUNTS = ["initramfs", "nfs", "cifs", "container", "local"]

  private def set_os_mount
    if is_docker_job?
      self.os_mount = "container"
      return
    end

    if self.os_mount?
      if !VALID_OS_MOUNTS.includes?(self.os_mount)
        raise "Invalid os_mount: #{self.os_mount}, should be in #{VALID_OS_MOUNTS}"
      end
    else
      self.os_mount = VALID_OS_MOUNTS[0]
    end
  end

  private def set_os_arch
    self.os_arch = self.arch if @hash_plain.has_key?("arch")
  end

  private def set_memory_minimum
    ["memory_minimum", "memory"].each do |_k|
      if @hash_plain.has_key?(_k)
        _memory = @hash_plain[_k].to_s.match(/\d+/)
        if _memory
          self.memory_minimum = _memory[0]
          return
        end
      end
    end

    if @hash_hh.has_key?("hw")
      _hw = @hash_hh["hw"].as(Hash)
      _memory = _hw["memory"].to_s.match(/\d+/)
      if _memory
        self.memory_minimum = _memory[0]
        return
      end
    end
  end

  private def set_os_version
    self.os_version = "#{os_version}".chomp("-iso") + "-iso" if self.os_mount == "local"
    self.osv = "#{os}@#{os_version}" # for easy ES search
  end

  private def check_docker_image
    return unless is_docker_job?

    # check docker image name
    image, tag = docker_image.split(":")
    known_os = YAML.parse(File.read("#{ENV["LKP_SRC"]}/rootfs/os.yaml")).as_h
    if known_os[self.os]? && known_os[self.os]["docker_image"]?
        known_image = known_os[self.os]["docker_image"].as_s
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
      if !@hash_plain[k]? || @hash_plain[k] == nil
        self[k] = v
      end
    end
  end

  private def extract_user_pkg
    return unless hh = @hash_hhh["pkg_data"]?

    # no check for now, release the comment when need that.
    # check_base_tag(hh["lkp-tests"]["tag"].to_s)

    hh.each do |repo, repo_pkg_data|
      next unless repo_pkg_data
      store_pkg(repo, repo_pkg_data)
      repo_pkg_data.delete("content")
    end
  end

  private def check_base_tag(user_tag)
    raise "
    \nyour lkp-tests code tag: #{user_tag} is not the latest release tag: #{BASE_TAG},
    \nyou can run the cmd \"git -C $LKP_SRC pull --ff-only\" to update your code,
    \notherwise you will can't use some new functions." unless user_tag == BASE_TAG
  end

  private def store_pkg(repo, repo_pkg_data)
    md5 = repo_pkg_data["md5"]

    dest_cgz_dir = "#{SRV_UPLOAD}/#{repo}/#{md5[0, 2]}"
    dest_cgz_file = "#{dest_cgz_dir}/#{md5}.cgz"

    return if File.exists? dest_cgz_file

    unless repo_pkg_data.has_key? "content"
      @upload_pkg_data << repo
      return
    end

    pkg_content_base64 = repo_pkg_data["content"]
    dest_cgz_content = Base64.decode_string(pkg_content_base64)

    FileUtils.mkdir_p(dest_cgz_dir) unless File.exists?(dest_cgz_dir)
    File.write(dest_cgz_file, dest_cgz_content)

    check_pkg_integrity(md5, dest_cgz_file)
  end

  private def check_pkg_integrity(md5, dest_cgz_file)
    dest_cgz_md5 = Digest::MD5.hexdigest(File.read dest_cgz_file)

    raise "check pkg integrity failed." if md5 != dest_cgz_md5
  end

  private def set_lkp_server
    # handle by me, then keep connect to me
    s = (@hash_hh["services"] ||= HashH.new)
  end

  private def set_sshr_info
    # ssh_pub_key will always be set (maybe empty) by submit,
    # if sshd is defined anywhere in the job
    return unless @hash_plain.has_key?("ssh_pub_key")

    s = self.services.as(Hash)
    s["sshr_port"] = ENV["SSHR_PORT"]
    s["sshr_port_base"] = ENV["SSHR_PORT_BASE"]
    s["sshr_port_len"] = ENV["SSHR_PORT_LEN"]

    return if @account_info.hash_any["found"]? == false

    set_my_ssh_pubkey
  end

  private def set_my_ssh_pubkey
    pub_key = self.ssh_pub_key?
    update_account_my_pub_key(pub_key)
    self.ssh_pub_key = @account_info.hash_array["my_ssh_pubkey"].first
  end

  private def update_account_my_pub_key(pub_key)
    return if pub_key.nil? || pub_key.empty?
    @account_info.hash_array["my_ssh_pubkey"] ||= [] of String
    return if @account_info.hash_array["my_ssh_pubkey"].includes?(pub_key)

    @account_info.hash_array["my_ssh_pubkey"] << pub_key
    @es.update_account(@account_info.to_json_any, self.my_email)
  end

  def os_dir
    return "#{os}/#{os_arch}/#{os_version}"
  end

  private def set_submit_date
    self.submit_date = Time.local.to_s("%F")
  end

  private def set_rootfs
    self.rootfs = "#{os}-#{os_version}-#{os_arch}"
  end

  def set_tbox_type
    if self.testbox.starts_with?("dc")
      self["tbox_type"] = "dc"
    elsif self.testbox.starts_with?("vm")
      self["tbox_type"] = "vm"
    else
      self["tbox_type"] = "hw"
    end
  end

  def get_testbox_type
    return "vm" if self.testbox.starts_with?("vm")
    return "dc" if self.testbox.starts_with?("dc")
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
      time = (self.timeout? || self.runtime? || 3600).to_s.to_i32
      extra_time = 0 if self.timeout?
      extra_time ||= [time / 8, 300].max.to_i32 + Math.sqrt(time).to_i32
    when "renew"
      return self.renew_deadline?
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

    self.deadline = deadline
  end

  # XXX: get/update ES, tell lifecycle
  def renew_deadline(time)
    deadline = Time.parse(self.deadline, "%Y-%m-%dT%H:%M:%S", Time.local.location)
    deadline = (deadline + time.to_i32.second).to_s("%Y-%m-%dT%H:%M:%S+0800")
    self.renew_deadline = deadline
    self.deadline = deadline
  end

  def set_result_root
    self.result_root = File.join("/result/#{suite}/#{submit_date}/#{tbox_group}/#{rootfs}", "#{sort_pp_params}", "#{id}")
    set_upload_dirs()
  end

  def get_pkg_common_dir
    tmp_style = nil
    ["cci-makepkg", "cci-depends", "build-pkg", "pkgbuild", "rpmbuild"].each do |item|
      tmp_style = @hash_any[item]?
      break if tmp_style
    end
    return nil unless tmp_style
    pkg_style = JobHash.new(tmp_style.as_h?)

    tmp_os = pkg_style["os"]? || self.os
    tmp_os_arch = pkg_style["os_arch"]? || self.os_arch
    tmp_os_version = pkg_style["os_version"]? || self.os_version

    mount_type = pkg_style["os_mount"]? || self.os_mount
    # same usage for client
    mount_type = "nfs" if mount_type == "cifs"

    common_dir = "#{mount_type}/#{tmp_os}/#{tmp_os_arch}/#{tmp_os_version}"
    common_dir = "#{tmp_os}-#{tmp_os_version}" if @hash_hhh["pp"]? && @hash_hhh["pp"].has_key?("rpmbuild")

    return common_dir
  end

  def get_upload_dirs_from_config
    _upload_dirs = ""
    upload_dirs_config = "#{ENV["CCI_SRC"]}/src/lib/upload_dirs_config.yaml"
    yaml_any_hash = YAML.parse(File.read(upload_dirs_config)).as_h
    yaml_any_hash.each do |k, v|
      if @hash_any.has_key?(k)
        _upload_dirs += ",#{v}"
      end
    end

    return _upload_dirs
  end

  def get_package_dir
    package_dir = ""
    common_dir = get_pkg_common_dir
    return package_dir unless common_dir

    # XXX
    if @hash_any["cci-makepkg"]?
      package_dir = ",/initrd/pkg/#{common_dir}/#{@hash_any["cci-makepkg"]["benchmark"]}"
    elsif @hash_any["cci-depends"]?
      package_dir = ",/initrd/deps/#{common_dir}/#{@hash_any["cci-depends"]["benchmark"]}"
    elsif @hash_any["rpmbuild"]?
      package_dir = ",/rpm/upload/#{common_dir}"
    elsif @hash_any["build-pkg"]? || @hash_any["pkgbuild"]?
      package_name = self.upstream_repo.split("/")[-1]
      package_dir = ",/initrd/build-pkg/#{common_dir}/#{package_name}"
      package_dir += ",/cci/build-config" if self.config?
        if self.upstream_repo =~ /^l\/linux\//
          package_dir += ",/kernel/#{os_arch}/#{self.config}/#{self.upstream_commit}"
      end
    end

    return package_dir
  end

  def set_time
    self.time = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
  end

  def set_time(key)
    self[key] = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
  end

  def get_repositories_dir
    if (@hash_any.has_key?("rpmbuild") || @hash_any.has_key?("hotpatch")) &&
        self.snapshot_id? && self.os_project? && self.os_variant?
      new_jobs = ",/repositories/new-jobs/"
      std_rpms = ",/repositories/#{self.os_project}/#{self.os_variant}/#{self.os_arch}/history/#{self.snapshot_id}/steps/upload/#{self.id}/"

      return "#{new_jobs}#{std_rpms}"
    end

    if self.upload_image_dir?
      return ",#{self.upload_image_dir}"
    end

    return ""
  end

  def set_upload_dirs
    self.upload_dirs = "#{result_root}#{get_package_dir}#{get_repositories_dir}#{get_upload_dirs_from_config}"
  end

  private def set_result_service
    self.result_service = "raw_upload"
  end

  private def set_queue
    return unless @hash_plain["queue"]?

    # set default value
    self.queue = self.tbox_group
    if self.tbox_group.starts_with?(/(vm|dc|vt)-/)
      self.queue = "#{self.tbox_group}.#{self.arch}"
    end
    #self.put_if_not_absent("queue", queue)
  end

  private def set_subqueue
    if @hash_plain["submit_user"]? == "vip" && @hash_plain["submit_role"]? == "maintainer" && @hash_plain["build_type"]? == "single"
      self.subqueue = "vip"
    else
      self.subqueue = self.my_email unless @hash_plain["subqueue"]? == "idle"
    end
  end

  private def set_secrets
    (@hash_hh["secrets"] ||= HashH.new)["my_email"] = self.my_email
  end

  private def is_docker_job?
    if self.tbox_group =~ /^dc/
      return true
    else
      return false
    end
  end

  # These will be present at early submit time.
  # Client must fill either tbox_group or testbox.
  # Server will fill services.
  REQUIRED_KEYS = %w[
    suite

    tbox_group
    os
    os_version

    my_account
    my_email
    my_name
    my_token
  ]

  private def check_required_keys
    update_tbox_group_from_testbox # id must exists, need update tbox_group
    REQUIRED_KEYS.each do |key|
      if !@hash_plain[key]?
        error_msg = "Missing required job key: '#{key}'."
        if ["my_email", "my_name", "my_token"].includes?(key)
          error_msg += "\nPlease refer to https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/apply-account.md"
        end
        raise error_msg
      end
    end
  end

  # if not assign tbox_group, set it to a match result from testbox
  #  ?if job special testbox, should we just set tbox_group=testbox
  private def update_tbox_group_from_testbox
    #self.tbox_group ||= JobHelper.match_tbox_group(testbox)
    self.put_if_not_absent("tbox_group", JobHelper.match_tbox_group(testbox))
  end

  private def check_fields_format
    return
  end

  private def check_run_time
    # only job.yaml for borrowing machine has the key: ssh_pub_key
    return unless @hash_plain.has_key?("ssh_pub_key")

    # the maxmum borrowing time is limited no more than 30 days.
    # case the runtime/sleep value count beyond the limit,
    # it will throw error message and prevent the submit for borrowing machine.
    # runtime value is converted to second.
    max_run_time = 30 * 24 * 3600
    error_msg = "\nMachine borrow time(runtime/sleep) cannot exceed 30 days. Consider re-borrow.\n"

    sleep_run_time = pp("sleep", "runtime") ||
                      pp("sleep", "args") ||
                      self.runtime? ||
                      self.timeout?

    return unless sleep_run_time

    # XXX: parse s/m/h/d/w suffix
    raise error_msg if to_seconds(sleep_run_time) > max_run_time
  end

  private def get_initialized_keys
    initialized_keys = [] of String
    initialized_keys.concat REQUIRED_KEYS
    initialized_keys.concat PLAIN_KEYS
    initialized_keys.concat ARRAY_KEYS
    initialized_keys.concat HH_KEYS
    initialized_keys.concat HHH_KEYS

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
    #self.kernel_version ||= File.basename(File.real_path "#{boot_dir}/vmlinuz").gsub("vmlinuz-", "")
    self.put_if_not_absent("kernel_version",  File.basename(File.real_path "#{boot_dir}/vmlinuz").gsub("vmlinuz-", ""))
  end

  private def set_kernel_uri
    return if @hash_plain.has_key?("kernel_uri")
    vmlinuz_path = File.real_path("#{boot_dir}/vmlinuz-#{kernel_version}")
    self.kernel_uri = "#{OS_HTTP_PREFIX}" + JobHelper.service_path(vmlinuz_path)
  end

  private def set_modules_uri
    return if @hash_array.has_key?("modules_uri")
    return if self.os_mount == "local"

    modules_path = File.real_path("#{boot_dir}/modules-#{kernel_version}.cgz")
    self.modules_uri = ["#{OS_HTTP_PREFIX}" + JobHelper.service_path(modules_path)]
  end

  # http://172.168.131.113:8800/kernel/aarch64/config-4.19.90-2003.4.0.0036.oe1.aarch64/v5.10/vmlinuz
  def update_kernel_uri(full_kernel_uri)
    self.kernel_uri = full_kernel_uri
  end

  # http://172.168.131.113:8800/kernel/aarch64/config-4.19.90-2003.4.0.0036.oe1.aarch64/v5.10/modules.cgz
  def update_modules_uri(full_modules_uri)
    self.modules_uri = full_modules_uri
  end

  def get_common_initrds
    temp_initrds = [] of String

    initrd_http_prefix = @is_remote ? ENV["DOMAIN_NAME"] : INITRD_HTTP_PREFIX
    sched_http_prefix = @is_remote ?  ENV["DOMAIN_NAME"] : SCHED_HTTP_PREFIX
    # init custom_bootstrap cgz
    # if has custom_bootstrap field, just give bootstrap cgz to testbox, no need lkp-test/job cgz
    if @hash_plain.has_key?("custom_bootstrap")
      raise "need runtime field in the job yaml." unless @hash_plain.has_key?("runtime")

      temp_initrds << "#{INITRD_HTTP_PREFIX}" +
        JobHelper.service_path("#{SRV_INITRD}/custom_bootstrap/#{self.my_email}/bootstrap-#{os_arch}.cgz")

      return temp_initrds
    end

    # init job.cgz
    temp_initrds << "#{sched_http_prefix}/job_initrd_tmpfs/#{id}/job.cgz"

    # pkg_data:
    #   lkp-tests:
    #     tag: v1.0
    #     md5: xxxx
    #     content: yyy (base64)
    raise "you should update your lkp-tests repo." unless @hash_hhh["pkg_data"]?

    @hash_hhh["pkg_data"].each do |key, value|
      next unless value
      program = value
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

    temp_initrds.concat(self.initrd_deps)
    temp_initrds.concat(self.initrd_pkgs)
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

    if self.os_mount == "initramfs"
      temp_initrds.concat(initramfs_initrds())
    elsif ["nfs", "cifs", "local"].includes? self.os_mount
      temp_initrds.concat(nfs_cifs_initrds())
    end

    temp_initrds.concat(get_common_initrds())

    return temp_initrds
  end

  private def initrds_basename : Array(String)
    return self.os_mount == "container" ? [] of String : get_initrds.map { |initrd| "initrd=#{File.basename(initrd)}" }
  end

  private def set_initrds_uri
    self.initrds_uri = get_initrds()
  end

  def append_initrd_uri(initrd_uri)
    self.initrds_uri << initrd_uri if self.os_mount == "initramfs"
    self.initrd_deps << initrd_uri
  end

  private def set_depends_initrd
    initrd_deps_arr = Array(String).new
    initrd_pkgs_arr = Array(String).new

    get_depends_initrd(get_program_params(), initrd_deps_arr, initrd_pkgs_arr)

    self.initrd_deps = initrd_deps_arr.uniq
    self.initrd_pkgs = initrd_pkgs_arr.uniq
  end

  private def get_program_params
    program_params = HashHH.new
    program_params.merge!(@hash_hhh["monitors"]) if @hash_hhh["monitors"]?
    program_params.merge!(@hash_hhh["pp"]) if @hash_hhh["pp"]?
    program_params
  end

  private def get_depends_initrd(program_params, initrd_deps_arr, initrd_pkgs_arr)
    initrd_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
    mount_type = self.os_mount == "cifs" ? "nfs" : self.os_mount

    # init deps lkp.cgz
    deps_lkp_cgz = "#{SRV_INITRD}/deps/#{mount_type}/#{self.os_dir}/lkp/lkp.cgz"
    if File.exists?(deps_lkp_cgz)
      initrd_deps_arr << "#{initrd_http_prefix}" + JobHelper.service_path(deps_lkp_cgz)
    end

    program_params.keys.each do |program|
      if program =~ /^(.*)-\d+$/
        program = $1
      end

      # XXX
      if @hash_any["#{program}_version"]?
        program_version = @hash_any["#{program}_version"].as_s
      else
        program_version = "latest"
      end

      deps_dest_file = "#{SRV_INITRD}/deps/#{mount_type}/#{self.os_dir}/#{program}/#{program}.cgz"
      pkg_dest_file = "#{SRV_INITRD}/pkg/#{mount_type}/#{self.os_dir}/#{program}/#{program_version}.cgz"

      if File.exists?(deps_dest_file)
        initrd_deps_arr << "#{initrd_http_prefix}" + JobHelper.service_path(deps_dest_file)
      end
      if File.exists?(pkg_dest_file)
        initrd_pkgs_arr << "#{initrd_http_prefix}" + JobHelper.service_path(pkg_dest_file)
      end
    end
  end

  def update_tbox_group(tbox_group)
    self.tbox_group = tbox_group

    # "result_root" is based on "tbox_group"
    #  so when update tbox_group, we need redo set_
    set_result_root()
  end

  def update_id(id)
    self.id = id

    # "result_root" => "/result/#{suite}/#{tbox_group}/#{date}/#{id}"
    # set_initrds_uri -> get_initrds -> common_initrds => ".../#{id}/job.cgz"
    #
    # "result_root, common_initrds" is associate with "id"
    #  so when update id, we need redo set_
    set_result_root()
    set_initrds_uri()
  end

  def update_kernel_params
    host_info = Utils.get_host_info(self.testbox)
    return unless host_info

    hw_job = JobHash.new({"hw" => host_info})
    set_crashkernel(Utils.get_crashkernel(host_info.as_h)) unless self.crashkernel?
    self.merge!(hw_job)
  end

  def set_crashkernel(p)
    self.crashkernel = p
  end

  def get_uuid_tag
    uuid = self["uuid"]
    uuid != "" ? "/#{uuid}" : nil
  end

  def delete_kernel_params
    @hash_plain.delete("kernel_version")
    @hash_plain.delete("kernel_uri")
    @hash_plain.delete("modules_uri")
  end

  def delete_host_info
    @hash_any.delete("hw")

    # XXX
    @hash_any.delete("memory")
    @hash_any.delete("nr_hdd_partitions")
    @hash_any.delete("hdd_partitions")
    @hash_any.delete("ssd_partitions")
    @hash_any.delete("rootfs_disk")
    @hash_any.delete("mac_addr")
    @hash_any.delete("arch")
    @hash_any.delete("nr_node")
    @hash_any.delete("nr_cpu")
    @hash_any.delete("model_name")
    @hash_any.delete("ipmi_ip")
    @hash_any.delete("serial_number")
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
        self.suite != "build-pkg" && self.suite != "pkgbuild"
      dest_dir = "#{SRV_USER_FILE_UPLOAD}/#{self.suite}/#{field_name}"
    else
      # XXX
      pkg_name = self.pkgbuild_repo.chomp.split('/', remove_empty: true)[-1]
      dest_dir = "#{SRV_USER_FILE_UPLOAD}/#{self.suite}/#{pkg_name}/#{field_name}"
    end
    return dest_dir
  end

  private def generate_upload_fields(field_config)
      uploaded_file_path_hash = Hash(String, String).new
      fields_need_upload = [] of String
      ss = Hash(String, Hash(String, String)).new
      #process upload file field from ss.*.config*
      ss = @hash_hhh["ss"] if @hash_hhh.has_key?("ss")
      ss.each do |pkg_name, pkg_params|
        next unless pkg_params
        pkg_params.each do |key, val|
          if key =~ /config.*/ && val != nil
            field_name = "ss.#{pkg_name}.#{key}"
            filename = File.basename(val.chomp)
            dest_file_path = "#{SRV_USER_FILE_UPLOAD}/#{self.suite}/#{field_name}/#{filename}"
            if File.exists?(dest_file_path)
                uploaded_file_path_hash[field_name] = dest_file_path
            else
              fields_need_upload << field_name
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
          next if _suite != self.suite || !@hash_any.has_key?(field_name)
          filename = File.basename(@hash_any[field_name].to_s.chomp)
          dest_dir = get_dest_dir(field_name)
          dest_file_path = "#{dest_dir}/#{filename}"
          if File.exists?(dest_file_path)
            uploaded_file_path_hash[field_name] = dest_file_path
          else
            fields_need_upload << field_name
          end
        end
      end
      return fields_need_upload, uploaded_file_path_hash
  end

  def process_user_files_upload
      process_upload_fields()
      #get field that can take upload file
      field_config = get_user_uploadfiles_fields_from_config()

      #get fields_need_upload that need upload ,such as ss.linux.config, ss.git.configxx
      #get uploaded file info, we can add it in initrds
      fields_need_upload, uploaded_file_path_hash = generate_upload_fields(field_config)
      fields_need_upload.concat @upload_pkg_data if @upload_pkg_data

      # if fields_need_upload size > 0, need upload ,return
      return fields_need_upload if !fields_need_upload.size.zero?

      #process if found file in server
      uploaded_file_path_hash.each do |field, filepath|
        # if field not match ss.*.config*, it is a simple job
        if !(field =~ /ss\..*\.config.*/)
          # construct initrd url for upload_file
          # save initrd url in env upload_file_url, for append in PKGBUILD source=()

          initrd_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
          upload_file_initrd = "#{initrd_http_prefix}#{JobHelper.service_path(filepath, true)}"
          @hash_any["upload_file_url"] = JSON::Any.new(upload_file_initrd)
        end
      end
  end

  # upload_fields:
  #   ss.linux.config:
  #     md5: xxx
  #     field_name: ss.xx.config* or pkgbuild config
  #     content: file content
  #     save_dir: /path/to/saved/content
  private def process_upload_fields
      return unless hh = @hash_hhh["upload_fields"]?

      hh.each do |field_name, upload_item|
        next unless upload_item
        upload_item["save_dir"] = store_upload_file(field_name, upload_item)
        upload_item.delete("content")
      end
  end

  private def store_upload_file(field_name, upload_item)
      md5 = upload_item["md5"]
      file_name = upload_item["file_name"]
      dest_dir = get_dest_dir(field_name)
      FileUtils.mkdir_p(dest_dir) unless File.exists?(dest_dir)
      dest_file = "#{dest_dir}/#{file_name}"

      #if file exist in server, check md5
      if File.exists?(dest_file)
        return dest_file
      end

      #save file
      content_base64 = upload_item["content"]
      dest_content = Base64.decode_string(content_base64)
      File.touch(dest_file)
      File.write(dest_file, dest_content)
      # verify save
      check_config_integrity(md5, dest_file)
      return dest_file
  end

end
