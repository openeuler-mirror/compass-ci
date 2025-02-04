# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2025 Huawei Technologies Co., Ltd. All rights reserved.

require "./utils.cr"
require "../scheduler/elasticsearch_client.cr"

# Static info describing a testbox (for hw machines) or tbox_group (for vm-* dc-*)
# - batch loaded from lab {hosts,devices}/* yaml
# - on-demand loaded from ES hosts/ index
# - on-demand updated on API register-host/, pass through to ES
class HostInfo

  # Internal hash members to store dynamic data
  property id : Int64 = 0
  @job_defaults : Hash(String, String) = Hash(String, String).new
  @hash_uint32 : Hash(String, UInt32) = Hash(String, UInt32).new
  @hash_str : Hash(String, String) = Hash(String, String).new
  @hash_str_array : Hash(String, Array(String)) = Hash(String, Array(String)).new
  @hash_bool : Hash(String, Bool) = Hash(String, Bool).new
  property hash_all : Hash(String, JSON::Any) = Hash(String, JSON::Any).new

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

    # Load integer properties
    hi.load_uint32(parsed_data, "nr_node")
    hi.load_uint32(parsed_data, "nr_cpu")
    hi.load_uint32(parsed_data, "nr_hdd_partitions")
    hi.load_uint32(parsed_data, "nr_ssd_partitions")
    hi.load_uint32(parsed_data, "active_time")

    # it may either be pure number, or number + g/G suffix
    hi.load_memory(parsed_data, "memory")

    # Load string properties
    hi.load_string(parsed_data, "arch")
    hi.load_string(parsed_data, "model_name")
    hi.load_string(parsed_data, "serial_number")

    # Load string array properties
    hi.load_mac(parsed_data, "mac_addr")
    hi.load_string_array(parsed_data, "rootfs_disk")
    hi.load_string_array(parsed_data, "hdd_partitions")
    hi.load_string_array(parsed_data, "ssd_partitions")

    hi.load_job_defaults(parsed_data)
    hi.load_id(parsed_data)

    hi.hash_all = parsed_data

    hi
  end

  def load_id(parsed_data)
    if parsed_data.has_key? "id"
      @id = parsed_data["id"].as_i64
    elsif @hash_str_array.has_key? "mac_addr"
      @id = mac_to_int64(self.mac_addr.first)
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

  def load_memory(parsed_data, key : String)
    value = parsed_data[key].as_s.to_i rescue nil
    @hash_uint32[key] = value.to_u32 if value
  end

  def load_uint32(parsed_data, key : String)
    value = parsed_data[key].as_i64 rescue nil
    @hash_uint32[key] = value.to_u32 if value
  end

  def load_bool(parsed_data, key : String)
    value = parsed_data[key].as_bool rescue nil
    @hash_str[key] = value if value
  end

  def load_string(parsed_data, key : String)
    value = parsed_data[key].as_s rescue nil
    @hash_str[key] = value if value
  end

  def load_mac(parsed_data, key : String)
    value = parsed_data[key].as_a.map(&.as_s) rescue nil
    @hash_str_array[key] = value.map { |v| Utils.normalize_mac(v) } if value
  end

  def load_string_array(parsed_data, key : String)
    value = parsed_data[key].as_a.map(&.as_s) rescue nil
    @hash_str_array[key] = value if value
  end

  FULL_TEXT_KEYS = %w[ model_name bios system baseboard cpu memory_info cards network disks ]

  def to_manticore
    mjob = @hash_all.dup
    mjob["id"] = JSON::Any.new(@id)

    @hash_uint32.keys.each do |field|
      mjob[field] = JSON::Any.new @hash_uint32[field]
    end

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

  # Mimic properties with instance methods
  def nr_node : UInt32?;                          @hash_uint32["nr_node"]; end
  def nr_cpu : UInt32?;                           @hash_uint32["nr_cpu"]; end
  def memory : UInt32?;                           @hash_uint32["memory"]; end
  def nr_hdd_partitions : UInt32?;                @hash_uint32["nr_hdd_partitions"]; end
  def nr_ssd_partitions : UInt32?;                @hash_uint32["nr_ssd_partitions"]; end

  def mac_addr : Array(String)?;                  @hash_str_array["mac_addr"]; end
  def rootfs_disk : Array(String)?;               @hash_str_array["rootfs_disk"]; end
  def hdd_partitions : Array(String)?;            @hash_str_array["hdd_partitions"]; end
  def ssd_partitions : Array(String)?;            @hash_str_array["ssd_partitions"]; end

  def arch : String?;                             @hash_str["arch"]; end
  def model_name : String?;                       @hash_str["model_name"]; end
  def serial_number : String?;                    @hash_str["serial_number"]; end

  # properties not from yaml
  def host_machine : String?;                     @hash_str["host_machine"]; end
  def host_machine=(value : String);              @hash_str["host_machine"] = value; end

  def hostname : String?;                         @hash_str["hostname"]; end
  def hostname=(value : String);                  @hash_str["hostname"] = value; end

  def tbox_type : String?;                        @hash_str["tbox_type"]; end
  def tbox_type=(value : String);                 @hash_str["tbox_type"] = value; end

  def is_remote : Bool?;                          @hash_bool["is_remote"].to_b; end
  def is_remote=(value : Bool);                   @hash_bool["is_remote"] = value.to_s; end

  # unit: MB, dynamic updated, only for qemu/docker host machines
  def freemem : UInt32?;                          @hash_uint32["freemem"]; end
  def freemem=(value : UInt32);                   @hash_uint32["freemem"] = value; end
  def active_time : UInt32?;                      @hash_uint32["active_time"]; end
  def active_time=(value : UInt32);               @hash_uint32["active_time"] = value; end

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
      end
  end

  def [](hostname : String) : HostInfo | Nil
    @hosts[hostname]
  end

  def mac2hostname(mac : String) : String | Nil
    return @mac2hostname[mac] if @mac2hostname.has_key? mac
    find_host_in_es({"mac_addr" => mac})
    @mac2hostname[mac]?
  end

  def get(hostname : String) : HostInfo | Nil
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

end

class Sched
  def register_host(host_hash : Hash(String, JSON::Any))
    host_info = HostInfo.from_parsed(host_hash)
    @hosts_cache.add_host(host_info)
    @es.set_host(host_info)
  end
end
