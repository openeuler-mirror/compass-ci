# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "yaml"
require "set"
require "any_merge"
require "digest"
require "base64"

# The 3 major stages are handled by
# - client submit incomplete job spec => Job class validate/amend/augment fields => save to @es and in-memory job caches
# - hw/provider hosts request for job => dispatch.cr select & move ready jobs from @jobs_cache_in_submit to @jobs_cache
# - hub.cr manages waiting/running jobs in @jobs_cache: wait/wakeup, update job fields on progress, forward watch log and remote login
class JobHash
end

require "./constants-manticore.cr"
require "../scheduler/constants.cr"
require "../scheduler/jobfile_operate.cr"
require "../scheduler/kernel_params.cr"
require "../scheduler/pp_params.cr"
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
    temp_path = need_exists ? File.realpath(path) : path
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
    #   monitor.vmstat: nil
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

  getter hash_int32 : Hash(String, Int32)
  getter hash_plain : Hash(String, String)
  getter hash_array : HashArray
  getter hash_hh : HashHH
  getter hash_hhh : HashHHH
  getter hash_any : Str2AnyHash

  # only in-memory, for matching to host tags
  property host_keys = Array(String).new
  property schedule_tags = Set(String).new
  property schedule_memmb : UInt32 = 0u32
  property schedule_priority : Int8 = 0

  # ES uses string id, so add in-memory id64 for convenience
  property id64 : Int64 = 0
  property is_remote = false

  def id_es
    self.id
  end

  INT32_SET = Set(String).new INT32_KEYS
  PLAIN_SET = Set(String).new PLAIN_KEYS
  ARRAY_SET = Set(String).new ARRAY_KEYS
  HH_SET    = Set(String).new HH_KEYS
  HHH_SET   = Set(String).new HHH_KEYS

  def initialize(job_content = nil)
    @hash_any   = Str2AnyHash.new
    @hash_int32 = Hash(String, Int32).new
    @hash_plain = Hash(String, String).new
    @hash_array = HashArray.new
    @hash_hh    = HashHH.new
    @hash_hhh   = HashHHH.new

    import2hash(job_content)

    if id = self.id?
      @id64 = id.to_i64
    end
  end

  def initialize(ajob : JobHash)
    @hash_any   = ajob.hash_any.dup
    @hash_int32 = ajob.hash_int32.dup
    @hash_plain = ajob.hash_plain.dup
    @hash_array = ajob.hash_array.dup
    @hash_hh    = ajob.hash_hh.dup
    @hash_hhh   = ajob.hash_hhh.dup
    @id64 = ajob.id64
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
      elsif INT32_SET.includes? k
        @hash_int32[k] = v.as_i
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
    @hash_int32.merge!(other_job.hash_int32)
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
    @hash_int32.each { |k, v| hash_all[k] = JSON::Any.new(v) }
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

  SENSITIVE_ACCOUNT_KEYS = Set.new %w[
    my_email
    my_name
    my_token
  ]

  # Only add new number fields here, to keep comptability with exising ES mapping
  INT32_KEYS = %w(
    istage
    ihealth
    priority
    renew_seconds
    timeout_seconds
    deadline_utc
  )

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
    host_tbox
    tbox_group
    testbox
    cluster
    queue

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
    job_step
    job_state
    job_stage
    job_health
    last_success_stage

    time
    submit_time
    download_time
    boot_time
    setup_time
    wait_peer_time
    running_time
    uploading_time
    post_run_time
    finish_time
    manual_check_time
    renew_time

    boot_seconds
    run_seconds

    my_account
    my_email
    my_name
    my_token

    ssh_pub_key
    custom_bootstrap

    runtime
    timeout

    config
    commit
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
    hostname
    host_machine
    tbox_type
    branch
    job_origin
    workflow_exec_id
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

    need_memory
    memory_minimum
    max_duration

    spec_file_name
    use_remote_tbox
    weight

    direct_macs
    direct_ips
    nr_nic
    nr_disk
    disk_size

    del_testbox
  )

  ARRAY_KEYS = %w(
    my_ssh_pubkey
    initrds_uri
    modules_uri
    initrd_deps
    initrd_pkgs
    kernel_params
    kernel_rpms_url

    target_machines
    cache_dirs

    milestones

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
    ss_wait_jobs
    cluster_jobs
    waited
    hw
    vt
    matrix
  )

  # ss = software stack, with build time options
  # pp = program.param, runtime params will impact results
  # (config options won't impact results shall start with '_')
  HHH_KEYS = %w(
    pp
    ss

    setup
    daemon
    monitor
    monitors
    program

    pkg_data
    upload_fields

    wait_on
    wait_options
    waited_jobs
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

  {% for name in INT32_KEYS %}
    def {{name.id}};              @hash_int32[{{name}}];      end
    def {{(name + "?").id}};      @hash_int32[{{name}}]?;     end
    def {{(name + "=").id}}(v);   @hash_int32[{{name}}] = v;  end
  {% end %}

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

  def export_trivial_fields(fields : Array(String))
    h = Hash(String, String).new
    fields.each do |k|
      next if SENSITIVE_ACCOUNT_KEYS.includes? k
      if @hash_plain.has_key? k
        h[k] = @hash_plain[k]
      elsif @hash_int32.has_key? k
        h[k] = @hash_int32[k].to_s
      end
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

  # Transform Elasticsearch job to Manticore format
  def to_manticore
    mjob = {} of String => JSON::Any

    MANTI_STRING_FIELDS.each do |field|
      next unless self.has_key?(field)
      mjob[field] = JSON::Any.new self[field]
    end

    MANTI_INT64_FIELDS.each do |field|
      next unless self.has_key?(field)

      if field.ends_with?("_time")
        mjob[field] = JSON::Any.new time_to_unix(self[field])
      else
        mjob[field] = JSON::Any.new self[field].to_i64
      end
    end

    MANTI_INT32_FIELDS.each do |field|
      next unless self.has_key?(field)

      if field.ends_with?("_seconds")
        mjob[field] = JSON::Any.new duration_to_seconds(self[field])
      else
        mjob[field] = JSON::Any.new self[field].to_i32
      end
    end

    # errid as space-separated string
    if self.has_key? "errid"
      mjob["errid"] = JSON::Any.new @hash_array["errid"].join(" ")
    end

    # Process nested fields (pp, ss)
    full_text_kv = [] of String
    full_text_kv += hh_to_kv_array("pp") if @hash_hhh.has_key? "pp"
    full_text_kv += hh_to_kv_array("ss") if @hash_hhh.has_key? "ss"

    # Remaining fields
    MANTI_STRING_FIELDS.each do |field|
      value = self[field]
      full_text_kv << "#{field}=#{value}"
    end
    MANTI_FULLTEXT_FIELDS.each do |field|
      next unless self.has_key?(field)

      value = self[field]
      full_text_kv << "#{field}=#{value}"
    end

    MANTI_FULLTEXT_ARRAY_FIELDS.each do |field|
      next unless @hash_array.has_key?(field)

      value = @hash_array[field]
      full_text_kv += value.map {|v| "#{field}=#{v}"}
    end

    mjob["full_text_kv"] = JSON::Any.new full_text_kv.join(" ")
    mjob["j"] = self.to_json_any

    mjob
  end

  def time_to_unix(time : String) : Int64
    Time.parse(time, "%Y-%m-%dT%H:%M:%S", Time.local.location).to_unix
  end

  def duration_to_seconds(duration : String) : Int64
    parts = duration.split(':').map { |part| part.to_i64 }
    if parts.size == 1
      parts[0]
    else
      parts[0] * 3600 + parts[1] * 60 + parts[2]
    end
  end

  def hh_to_kv_array(field)
    hash = @hash_hhh[field]
    return [] of String unless hash.is_a?(Hash)

    hash.flat_map do |k1, inner|
      next [] of String unless inner.is_a?(Hash)

      inner.map do |k2, v|
        "#{field}.#{k1}.#{k2}=#{v}"
      end
    end
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

  # if not assign tbox_group, set it to a match result from testbox
  #  ?if job special testbox, should we just set tbox_group=testbox
  def update_tbox_group_from_testbox
    #self.tbox_group ||= JobHelper.match_tbox_group(testbox)
    self.put_if_not_absent("tbox_group", JobHelper.match_tbox_group(testbox))
  end

  def set_memmb
    mb = 0u32
    mb = [mb, Utils.parse_memory_mb(self.need_memory)].max if self.has_key? "need_memory"
    mb = [mb, Utils.parse_memory_mb(self.memory_minimum)].max if self.has_key? "memory_minimum"
    if self.tbox_group =~ /^(vm|dc)-(\d+)p(\d+)g$/
      mb = [mb, $3.to_u32].max
    end
    @schedule_memmb = mb
  end

  def set_priority
    if self.priority
      @schedule_priority = self.priority.to_i8
    end
  end

  # End user can control condidate hots that can consume the job via "submit job.yaml testbox=xxx"
  # testbox=taishan200-2280-2s64p-256g--a61: want the exact machine, register to hostkey $testbox
  # testbox=taishan200-2280-2s64p-256g: want anyone in the tbox_group, register to hostkey $tbox_group
  # testbox=hw|vm|dc: register to hostkey tbox_type.arch
  def set_hostkeys
    host_keys = [] of String

    case self.tbox_type
    when "hw"
      host_keys << self.testbox if self.testbox != self.tbox_group
      host_keys << self.tbox_group
    else
      host_keys << "#{self.tbox_type}.#{self.arch}"
    end

    if self.has_key? "target_machines"
      host_keys += self.target_machines
    end

    self.host_keys = host_keys
  end

  def set_time
    self.time = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
  end

  def set_time(key)
    self[key] = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
  end

  def set_boot_seconds
    return unless self.boot_time?
    return unless self.running_time?
    return unless self.finish_time?

    boot_time =     Time.parse(self.boot_time,    "%Y-%m-%dT%H:%M:%S", Time.local.location)
    running_time =  Time.parse(self.running_time, "%Y-%m-%dT%H:%M:%S", Time.local.location)
    finish_time =   Time.parse(self.finish_time,  "%Y-%m-%dT%H:%M:%S", Time.local.location)

    self.boot_seconds = (running_time - boot_time).to_s
    self.run_seconds = (finish_time - running_time).to_s
  end

  def get_runtime() : Int32 | Nil
    return self.runtime.to_i if self.has_key? "runtime"
    return unless @hash_hhh.has_key? "pp"

    runtime = 0
    self.pp.each do |_prog, v|
      runtime += v["runtime"].to_i if v && v.has_key? "runtime"
    end

    if runtime > 0
      return runtime
    else
      return nil
    end
  end

  def set_timeout_seconds
    if self.has_key? "timeout"
      return self.timeout_seconds = to_seconds(self.timeout)
    end

    secs = get_runtime
    if secs
      return self.timeout_seconds = secs + ([secs // 8, 300].max) + Math.sqrt(secs).to_i32
    end

    self.timeout_seconds = JOB_STAGE_TIMEOUT["running"]
  end

  def renew_addtime(secs)
    if self.renew_seconds?
      self.renew_seconds += secs
    else
      self.renew_seconds = secs
    end
  end

  # deadline_utc is a dynamic value, it will be regularly checked and refreshed
  # in lifecycle terminate_timeout_jobs()
  def set_deadline
    self.deadline_utc = Time.utc.to_unix.to_i32 + self.timeout_seconds
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

  def settle_job_fields(hostreq : HostRequest)
    self.host_machine = hostreq.hostname
    self.update_kernel_params

    self.is_remote = hostreq.is_remote
    self.set_depends_initrd()
    self.set_kernel()
    self.set_initrds_uri()
    self.set_remote_mount_repo()
    self.set_deadline()
  end

end

class Job < JobHash

  def initialize(job_content, id : String|Nil)
    super(job_content)

    unless id.nil?
      @hash_plain["id"] = id
      @id64 = id.to_i64
    end

    @es = Elasticsearch::Client.new
    @upload_pkg_data = Array(String).new
  end

  def submit(id = "-1")
    # init job with "-1", or use the original job.id
    self.id = id
    self.id64 = id.to_i64
    self.job_state = "submit"
    self.job_stage = "submit"
    self.istage = JOB_STAGE_NAME2ID["submit"] || 0

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

    check_run_time()
    set_defaults()
    delete_account_info()
    checkout_max_run()
  end

  def set_defaults
    extract_user_pkg()
    append_init_field()
    set_os_mount()
    set_os_arch()
    set_os_version()
    check_docker_image()
    set_time("submit_time")
    set_submit_date() # need by set_result_root()
    set_timeout_seconds()
    set_rootfs()
    set_result_root()
    set_result_service()
    set_lkp_server()
    set_sshr_info()
    check_queue()
    set_secrets()
    set_params_md5()
    set_memory_minimum()
  end

  def delete_account_info
    SENSITIVE_ACCOUNT_KEYS.each do |k|
      @hash_plain.delete(k)
    end
  end

  private def checkout_max_run
    return unless self.max_run?

    query = {
      "index" => "jobs",
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
  end

  private def set_submit_date
    self.submit_date = Time.local.to_s("%F")
  end

  private def set_rootfs
    self.rootfs = "#{os}-#{os_version}-#{os_arch}"
  end

  def get_testbox_type
    return "vm" if self.testbox.starts_with?("vm")
    return "dc" if self.testbox.starts_with?("dc")
    return "physical"
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

  private def check_queue
    return unless q = @hash_plain["queue"]?
    return if Sched::GREEN_QUEUES.includes? q

    # remove invalid queue
    @hash_plain.delete "queue"
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
    REQUIRED_KEYS.each do |key|
      if !@hash_plain[key]?
        error_msg = "Missing required job key: '#{key}'."
        if SENSITIVE_ACCOUNT_KEYS.includes?(key)
          error_msg += "\nPlease refer to https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/apply-account.md"
        end
        raise error_msg
      end
    end
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

  def update_tbox_group(tbox_group)
    self.tbox_group = tbox_group

    # "result_root" is based on "tbox_group"
    #  so when update tbox_group, we need redo set_
    set_result_root()
  end

  def update_id(id)
    self.id = id
    self.id64 = id.to_i64

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
    @user_uploadfiles_fields_config ||= begin
      user_uploadfiles_fields_config = "#{ENV["CCI_SRC"]}/src/lib/user_uploadfiles_fields_config.yaml"
      YAML.parse(File.read(user_uploadfiles_fields_config)).as_a
    end
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
          filename = File.basename(field_hash[field_name].to_s.chomp)
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
