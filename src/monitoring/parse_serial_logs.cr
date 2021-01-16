# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../scheduler/elasticsearch_client"
require "set"
require "json"

# This parses dmesg in a stream of serial log, finding a number of patterns
# in various places of the dmesg and take actions accordingly.
#     dmesg                                      action
# ==================================================================================
# START_PATTERN               close @host2file[host]; cache line to @host2head[host]
# header lines w/o job info   cache line to @host2head[host]
# JOB_PATTERN                 get job_id --> job --> result_root; dump cache to file
# dmesg lines w/ job info     append line to dmesg file under result_root;
# CRASH_PATTERN               notify oops/crash/warn --> reboot machine
# END_PATTERN                 close @host2file[host]
# ==================================================================================
# steps for a dmesg:
# 1) stash the head of dmesg file to hash before getting the job_id.
# 2) create dmesg file under the result_root of the job when successfully
#    matched the job_id from the received message.
# 3) detect kernel oops/crash and the end of dmesg file.

class SerialParser
  START_PATTERNS = [
    "starting QEMU",
    "starting DOCKER",
    "Start PXE over IPv4",
    "iPXE initialising devices",
    "Open Source Network Boot Firmware",
    "BIOS Build Version:",
    "BIOS Log @ ",
  ]

  END_PATTERNS = [
    "Total QEMU duration: ",
    "Total DOCKER duration: ",
    "No job now",
    "Restarting system",
  ]

  def initialize
    @host2head = Hash(String, Array(String)).new
    @host2rt = Hash(String, String).new
  end

  def host_in_msg(msg)
    return unless msg["serial_path"]?

    File.basename(msg["serial_path"].to_s)
  end

  def detect_start_or_end(msg, host, pattern_list)
    message = msg["message"].to_s
    pattern_list.each do |pattern|
      matched = message.match(/.*(?<signal>#{pattern})/)
      return matched.named_captures["signal"] unless matched.nil?
    end
  end

  def delete_host(msg, host, signal)
    boundary_signal = detect_start_or_end(msg, host, signal)
    return unless boundary_signal

    @host2head.delete(host)
    @host2rt.delete(host)
  end

  def save_dmesg_to_result_root(msg)
    host = host_in_msg(msg)
    return unless host

    delete_host(msg, host, START_PATTERNS)

    check_save = check_save_dmesg(msg, host)
    delete_host(msg, host, END_PATTERNS)
    return if check_save

    job_id = match_job_id(msg)
    job = find_job(job_id)
    return if dump_cache(job, msg, host)

    cache_dmesg(msg, host)
  end

  def check_save_dmesg(msg, host)
    return unless @host2rt.has_key?(host)

    File.open("#{@host2rt[host]}/dmesg", "a+") do |f|
      f.puts msg["message"]
    end
    return true
  end

  def match_job_id(msg)
    matched = msg["message"].to_s.match(/.*\/job_initrd_tmpfs\/(?<job_id>.*?)\//)
    return unless matched

    matched.named_captures["job_id"]
  end

  def find_job(job_id)
    return unless job_id

    Elasticsearch::Client.new.get_job_content(job_id)
  end

  def dump_cache(job, msg, host)
    return unless job

    result_root = File.join("/srv", job["result_root"].to_s)
    @host2rt[host] = result_root
    File.open("#{result_root}/dmesg", "w") do |f|
      f.puts @host2head[host].join("\n")
      f.puts msg["message"]
    end
    @host2head.delete(host)
    return true
  end

  def cache_dmesg(msg, host)
    @host2head[host] ||= Array(String).new
    @host2head[host] << msg["message"].to_s
  end
end
