# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2025 Huawei Technologies Co., Ltd. All rights reserved.

require "./lib/utils.cr"
require "./elasticsearch_client.cr"

# Static info describing a testbox (for hw machines) or tbox_group (for vm-* dc-*)
# - batch loaded from lab {hosts,devices}/* yaml
# - on-demand loaded from ES hosts/ index
# - on-demand updated on API register-host/, pass through to ES
class HostInfo

  # Internal hash members to store dynamic data
  property id : Int64 = 0
  property job_id : Int64 = 0
  @job_defaults : Hash(String, String) = Hash(String, String).new
  property hash_uint32 : Hash(String, UInt32) = Hash(String, UInt32).new
  property hash_str : Hash(String, String) = Hash(String, String).new
  property hash_str_array : Hash(String, Array(String)) = Hash(String, Array(String)).new
  property hash_bool : Hash(String, Bool) = Hash(String, Bool).new
  property hash_all : Hash(String, JSON::Any) = Hash(String, JSON::Any).new

  def id64
    @id
  end

  def id_es
    @id
  end

  # memory unit: MB
  # please keep UINT32_KEYS in sync with sbin/manti-table-hosts.sql
  UINT32_KEYS = %w(
    nr_node
    nr_cpu
    memory
    nr_disks
    nr_hdd_partitions
    nr_ssd_partitions

    nr_vm
    nr_container

    boot_time
    reboot_time
    active_time
  )

  # freemem unit: MB, dynamic updated, only for qemu/docker host machines
  UINT32_METRIC_KEYS = %w(
    freemem
    freemem_percent
    disk_max_used_percent
    cpu_idle_percent
    cpu_iowait_percent
    cpu_system_percent
    disk_io_util_percent
    network_util_percent
    network_errors_per_sec
    uptime_minutes
  )

  STR_ARRAY_KEYS = %w(
    mac_addr
    rootfs_disk
    hdd_partitions
    ssd_partitions
  )

  STRING_KEYS = %w(
    arch
    model_name
    serial_number
    hostname
    tbox_type

    ip
    suite
    my_account
    result_root

    disk_max_used_string
  )

  BOOL_KEYS = %w(
    is_remote
  )

  # Load HostInfo from a YAML file
  def self.from_yaml(file_path : String) : HostInfo
    yaml_data = File.read(file_path)
    parsed_hosts = YAML.parse(yaml_data).as_h

    devices_file = file_path.sub("/hosts/", "/devices/")
    if File.exists?(devices_file)
      yaml_data = File.read(file_path)
      parsed_devices = YAML.parse(yaml_data).as_h
      parsed_devices.delete "id"
      parsed_hosts = parsed_devices.merge(parsed_hosts)
    end

    host_info = from_parsed(JSON.parse(parsed_hosts.to_json).as_h)

    hostname = File.basename(file_path)
    host_info.hostname = hostname
    host_info.tbox_type = HostInfo.determine_tbox_type(hostname)
    host_info
  end

  # - YAML from lab git hosts/* files
  # - JSON from API request or ES/manticore query
  def self.from_parsed(parsed_data : Hash(String, JSON::Any)) : HostInfo
    hi = HostInfo.new

    BOOL_KEYS.each      do |key| hi.load_bool(parsed_data, key) end
    UINT32_KEYS.each    do |key| hi.load_uint32(parsed_data, key) end
    STRING_KEYS.each    do |key| hi.load_string(parsed_data, key) end
    STR_ARRAY_KEYS.each do |key| hi.load_string_array(parsed_data, key) end

    hi.load_job_defaults(parsed_data)
    hi.load_id(parsed_data)

    hi.hash_all = parsed_data

    hi
  end

  def load_id(parsed_data)
    if parsed_data.has_key? "id"
      @id = parsed_data["id"].as_i64
    else
      @id = Manticore.hash_string_to_i64(self.hostname)
    end
  end

  def mac_to_int64(mac : String) : Int64
    # Remove colons from the MAC address string
    hex_string = mac.gsub(":", "")
    # Convert the hexadecimal string to an UInt32
    hex_string.to_i64(16)
  end

  def load_job_defaults(parsed_data)
    return unless hash = parsed_data["job_defaults"]?
    hash.as_h.each { |k, v| @job_defaults[k] = v.as_s }
  end

  def load_uint32(parsed_data, key : String)
    if (key == "memory")
      # it may either be pure number, or number + g/G suffix
      value = Utils.parse_memory_mb(parsed_data[key].as_s).to_i rescue nil
    else
      value = parsed_data[key].as_i64 rescue nil
    end
    @hash_uint32[key] = value.to_u32 if value
  end

  def load_bool(parsed_data, key : String)
    value = parsed_data[key].as_bool rescue nil
    @hash_bool[key] = value if value
  end

  def load_string(parsed_data, key : String)
    value = parsed_data[key].as_s rescue nil
    @hash_str[key] = value if value
  end

  def load_string_array(parsed_data, key : String)
    value = parsed_data[key].as_a.map(&.as_s) rescue nil
    if (key == "mac_addr")
      @hash_str_array[key] = value.map { |v| Utils.normalize_mac(v) } if value
    else
      @hash_str_array[key] = value if value
    end
  end

  FULL_TEXT_KEYS = %w[ model_name bios system baseboard cpu memory_info cards network disks ]

  # please keep top level key assignments in sync with sbin/manti-table-hosts.sql
  def to_manticore
    mjob = @hash_all.dup
    mjob["id"] = JSON::Any.new(@id)

    @hash_uint32.keys.each do |field|
      mjob[field] = JSON::Any.new @hash_uint32[field]
    end
    mjob["job_id"] = JSON::Any.new(@job_id)

    full_text_kv = Manticore::FullTextWords.create_full_text_kv(mjob, FULL_TEXT_KEYS)

    # Remaining fields
    full_text_kv << "arch=#{self.arch}" if self.arch
    full_text_kv << "hostname=#{self.hostname}"
    self.mac_addr.each do |v|
      full_text_kv << "mac_addr=#{v}"
    end

    mjob["full_text_kv"] = JSON::Any.new full_text_kv.join(" ")
    mjob["j"] = self.to_json_any

    mjob
  end

  def merge2hash_all
    hash_all = @hash_all.dup
    hash_all["id"] = JSON::Any.new(@id)
    @hash_uint32.each { |k, v| hash_all[k] = JSON::Any.new(v) }
    @hash_bool.each { |k, v| hash_all[k] = JSON::Any.new(v) }
    @hash_str.each { |k, v| hash_all[k] = JSON::Any.new(v) }
    @hash_str_array.each do |k, v|
      hash_all[k] ||= JSON::Any.new([] of JSON::Any)
      hash_all[k].as_a.concat(v.map {|vv| JSON::Any.new(vv)})
    end

    hash_all["job_defaults"] ||= JSON::Any.new({} of String => JSON::Any)
    hash_all["job_defaults"].as_h.any_merge!(@job_defaults)

    hash_all
  end

  def to_json
    merge2hash_all.to_json
  end

  def to_json_any
    JSON.parse(self.to_json)
  end

  # Getter methods for accessing dynamic properties
  def [](key : String) : Bool? | UInt32? | String? | Array(String)?
    if @hash_uint32.has_key?(key)
      @hash_uint32[key]
    elsif @hash_str.has_key?(key)
      @hash_str[key]
    elsif @hash_str_array.has_key?(key)
      @hash_str_array[key]
    else
      nil
    end
  end

  def []=(key : String, value : Bool | UInt32 | String | Array(String))
    case value
    when UInt32
      @hash_uint32[key] = value
    when String
      @hash_str[key] = value
    when Array(String)
      @hash_str_array[key] = value
    end
  end

  # Generate methods for UInt32 properties
  {% for name in UINT32_KEYS + UINT32_METRIC_KEYS %}
    def {{name.id}} : UInt32
      @hash_uint32[{{name}}]
    end

    def {{name.id + "?"}} : UInt32?
      @hash_uint32[{{name}}]?
    end

    def {{(name + "=").id}}(value : UInt32)
      @hash_uint32[{{name}}] = value
    end
  {% end %}

  # Generate methods for Array(String) properties
  {% for name in STR_ARRAY_KEYS %}
    def {{name.id}};              @hash_str_array[{{name}}];      end
    def {{(name + "?").id}};      @hash_str_array[{{name}}]?;     end
    def {{(name + "=").id}}(v);   @hash_str_array[{{name}}] = v;  end
  {% end %}

  # Generate methods for String properties
  {% for name in STRING_KEYS %}
    def {{name.id}};              @hash_str[{{name}}];      end
    def {{(name + "?").id}};      @hash_str[{{name}}]?;     end
    def {{(name + "=").id}}(v);   @hash_str[{{name}}] = v;  end
  {% end %}

  # Generate methods for Bool properties
  {% for name in BOOL_KEYS %}
    def {{name.id}} : Bool
      @hash_bool.has_key?({{name}}) &&
      @hash_bool[{{name}}]
    end

    def {{name.id + "?"}} : Bool?
      @hash_bool[{{name}}]?
    end

    def {{(name + "=").id}}(value : Bool)
      @hash_bool[{{name}}] = value
    end
  {% end %}

  def self.determine_tbox_type(hostname : String) : String
    case hostname
    when /^dc-/ then
      "dc"
    when /^vm-/ then
      "vm"
    else
      "hw"
    end
  end

end

class Hosts
  property hosts
  property mac2hostname
  @hosts : Hash(String, HostInfo)
  @mac2hostname : Hash(String, String)
  @es : Elasticsearch::Client

  def initialize(es)
    @es = es
    @hosts = Hash(String, HostInfo).new
    @mac2hostname = Hash(String, String).new

    # example pattern: /c/cci/lab-z9/hosts/*
    Dir.glob("#{CCI_REPOS}/#{LAB_REPO}/hosts/*") do |file|
      next unless File.exists?(file)

      host_info = HostInfo.from_yaml(file)
      next unless host_info

      add_host(host_info)
    end
    @hosts
  end

  def add_host(host_info : HostInfo)
      @hosts[host_info.hostname] = host_info
      host_info.mac_addr.each do |mac|
        @mac2hostname[mac] = host_info.hostname
      end if host_info.hash_str_array.has_key? "mac_addr"
  end

  def []?(hostname : String) : HostInfo | Nil
    @hosts[hostname]?
  end

  def [](hostname : String) : HostInfo
    @hosts[hostname]
  end

  def mac2hostname(mac : String) : String | Nil
    return @mac2hostname[mac] if @mac2hostname.has_key? mac
    find_host_in_es({"mac_addr" => mac})
    @mac2hostname[mac]?
  end

  def get_host(hostname : String) : HostInfo | Nil
    return @hosts[hostname] if @hosts.has_key? hostname
    find_host_in_es({"hostname" => hostname})
    @hosts[hostname]?
  end

  def find_host_in_es(matches : Hash(String, String)) : HostInfo | Nil
    results = @es.select("hosts", matches)
    results.each do |hit|
      host = HostInfo.from_parsed(hit["_source"].as_h)
      add_host(host)
    end
  end

  def update_job_info(job)
    return unless job.tbox_type == "hw"

    host = get_host(job.hostname)
    return unless host

    host.job_id = job.id64
    host.suite = job.suite
    host.my_account = job.my_account
    host.result_root = job.result_root
    host.boot_time = Time.local.to_unix.to_u32
    # host.reboot_time = job.deadline
  end

  def pass_info_to_host(host_req, msg)
    hostinfo = get_host(host_req.hostname)
    unless hostinfo
      hostinfo = HostInfo.from_parsed(msg)
      add_host hostinfo
    end

    # Pass on metrics from provider websocket regular messages.
    # HW machine metrics are not reported together in msg, but via api_register_host() "report_metrics" case.
    if host_req.tbox_type != "hw"
      HostInfo::UINT32_METRIC_KEYS.each do |key|
        hostinfo.hash_uint32[key] =
        host_req.metrics[key] if host_req.metrics.has_key? key
      end
      hostinfo.hash_str["disk_max_used_string"] = host_req.disk_max_used_string unless host_req.disk_max_used_string.empty?
      hostinfo.freemem = host_req.freemem
    end
  end
end

class Sched
  def update_host_metrics(hostname : String, hash : Hash(String, JSON::Any)) : Result
    unless @hosts_cache.hosts.has_key?(hostname)
      return Result.error(HTTP::Status::NOT_FOUND, "Host not found: #{hostname}")
    end

    hi = @hosts_cache[hostname]
    HostInfo::UINT32_METRIC_KEYS.each do |key|
      hi.load_uint32(hash, key)
    end
    ["disk_max_used_string"].each do |key|
      hi.load_string(hash, key)
    end

    Result.success("Metrics updated for host: #{hostname}")
  end

  def api_register_host(hostname : String, host_hash : Hash(String, JSON::Any), for_metrics : Bool) : Result
    begin
      if for_metrics
        # Update metrics for an existing host
        return update_host_metrics(hostname, host_hash)
      else
        # Register a new host
        host_info = HostInfo.from_parsed(host_hash)
        @hosts_cache.add_host(host_info)
        @es.replace_doc("hosts", host_info)
      end

      Result.success("Host registered successfully: #{hostname}")
    rescue ex
      # Log the error for debugging
      Log.error(exception: ex) { "Failed to register host: #{hostname}" }
      Result.error(HTTP::Status::INTERNAL_SERVER_ERROR, ex.message || "Internal server error")
    end
  end
end
