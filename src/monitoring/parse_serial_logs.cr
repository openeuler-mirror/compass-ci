# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../scheduler/elasticsearch_client"
require "set"
require "json"
require "../lib/mq"
require "../lib/json_logger"

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

  CRASH_PATTERNS = [
    "Kernel panic - not syncing:",
  ]

  def initialize
    @host2head = Hash(String, Array(String)).new
    @host2rt = Hash(String, String).new
    @host2file = Hash(String, File).new
    @mq = MQClient.instance
    @log = JSONLogger.new
  end

  def host_in_msg(msg)
    return unless msg["serial_path"]?

    File.basename(msg["serial_path"].to_s)
  end

  def detect_patterns(msg, pattern_list)
    message = msg["message"].to_s
    pattern_list.each do |pattern|
      matched = message.match(/.*(?<signal>#{pattern})/)
      return matched.named_captures["signal"] unless matched.nil?
    end
  end

  def is_signal?(msg, pattern_list)
    message = msg["message"].to_s
    pattern_list.each do |pattern|
      return true if message.includes?(pattern)
    end
  end

  def delete_host(msg, host, signal)
    return unless is_signal?(msg, signal)

    close_file(host)
    @host2head.delete(host)
    @host2rt.delete(host)
  end

  def close_file(host)
    return unless @host2file.has_key?(host)

    @host2file[host].close
    @host2file.delete(host)
  end

  def mq_publish(msg, host)
    crash_signal = detect_patterns(msg, CRASH_PATTERNS)
    return unless crash_signal

    job_id = ""
    if @host2rt.has_key?(host)
      job_id = File.basename(@host2rt[host])
    end

    mq_msg = {
      "job_id" => job_id,
      "testbox" => host,
      "time" => msg["time"]? || Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800"),
      "job_stage" => "unknow",
      "job_health" => "crash",
      "message" => msg["message"]
    }.to_json

    @log.info(mq_msg)
    spawn mq_publish_check("job_mq", mq_msg)
  end

  def mq_publish_check(queue, msg)
    3.times do
      @mq.publish_confirm(queue, msg)
      break
    rescue e
      res = @mq.reconnect
      sleep 5
    end
  end

  def deal_serial_log(msg)
    host = host_in_msg(msg)
    return unless host

    save_dmesg_to_result_root(msg, host)
    mq_publish(msg, host)
  end

  def save_dmesg_to_result_root(msg, host)
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
    return unless @host2file.has_key?(host)

    @host2file[host].puts msg["message"]
    @host2file[host].flush
    return true
  end

  def match_job_id(msg)
    matched = msg["message"].to_s.match(/.*\/job_initrd_tmpfs\/(?<job_id>.*?)\//)
    if matched
      return matched.named_captures["job_id"]
    end

    matched = msg["message"].to_s.match(/ipxe will boot job id=(?<job_id>[a-zA-Z0-9-]+\.[0-9]+), /)
    if matched
      return matched.named_captures["job_id"]
    end

    return nil
  end

  def find_job(job_id)
    return unless job_id

    Elasticsearch::Client.new.get_job(job_id)
  end

  def dump_cache(job, msg, host)
    return unless job

    result_root = File.join("/srv", job.result_root)
    @host2rt[host] = result_root

    f = File.new("#{result_root}/dmesg", "a")
    f.puts @host2head[host].join("\n")
    f.puts msg["message"]
    f.flush

    @host2file[host] = f
    @host2head.delete(host)
    return true
  end

  def cache_dmesg(msg, host)
    @host2head[host] ||= Array(String).new
    @host2head[host] << msg["message"].to_s
  end
end
