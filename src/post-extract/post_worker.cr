# SPDX-License-Identifier: GPL-2.0-only
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "yaml"
require "http/client"

require "../lib/etcd_client"
require "../lib/json_logger"
require "../scheduler/elasticsearch_client"

class PostWorker
  def initialize
    @es = Elasticsearch::Client.new
    @etcd = EtcdClient.new
    @log = JSONLogger.new
  end

  def handle(queue_path, channel)
    begin
      res = @etcd.range(queue_path)
      return nil if res.count == 0

      job_id = queue_path.split("/")[-1]
      job = @es.get_job(job_id)
      return unless job
      
      # send email while necessary
      get_pr_result(job)
      # send post-extract event to specific queue for workflow runner
      send_workflow_event(job_id, job)

      @log.info("post-extract delete key from etcd, the queue is #{job_id}")
      @etcd.delete(queue_path)
    rescue e
      channel.send(queue_path)
      @log.error(e.message)
      # incase of many error message when ETCD, ES does not work
      sleep(10.seconds)
    ensure
      @etcd.close
    end
  end

  def pack_post_extract_event(job_id, job)
    workflow_exec_id = job.workflow_exec_id?
    return if workflow_exec_id.nil? || workflow_exec_id.empty?

    job_name_regex = /\/([^\/]+)\.(yaml|yml|YAML|YML)$/
    job_origin = job.job_origin?
    return if job_origin.nil? || job_origin.empty?

    job_name_match = job_origin.match(job_name_regex)
    job_name = job_name_match ? job_name_match[1] : nil
    return unless !job_name.nil?

    job_stage = job.job_stage?
    job_health = job.job_health?
    job_result = job.result_root?
    job_nickname = job.nickname?

    return unless job_stage == "finish"

    begin
      job_matrix = job.matrix?
      job_matrix = job.matrix?.to_json
    rescue
    end

    job_branch = job.branch?
    
    fingerprint = {
      "type" => "job/stage",
      "job_stage" => "post-extract",
      "job_health" => job_health,
      "job" => job_name,
      "workflow_exec_id" => workflow_exec_id,
    }
    fingerprint = fingerprint.merge({"nickname" => job_nickname}) if !job_nickname.nil? && !job_nickname.empty?
    
    packed_event = {
      "fingerprint" => fingerprint,
      "job_id" => job_id,
      "job" => job_name,
      "type" => "job/stage",
      "job_stage" => "post-extract",
      "job_health" => job_health,
      "nickname" => job_nickname,
      "branch" => job_branch,
      "result_root" => job_result,
      "workflow_exec_id" => workflow_exec_id,
    }
    packed_event.merge!({"job_matrix" => job_matrix}) unless job_matrix.nil?

    packed_event
  end

  def send_workflow_event(job_id, job)
    workflow_exec_id = job.workflow_exec_id?
    return if workflow_exec_id.nil? || workflow_exec_id.empty?

    post_extract_event = pack_post_extract_event(job_id, job)
    if post_extract_event
      @etcd.put_not_exists("raw_events/job/#{job_id}", post_extract_event.to_json)
      @log.info("reported post-extract event, id: #{job_id}")
    end
  end

  def get_pr_result(job)
    return unless job.pr_merge_reference_name?
    return unless job.upstream_dir? == "openeuler"

    send_email(job)
  end

  def send_email(job)
    msg = build_email_msg(job)
    send_mail_host = %x(/sbin/ip route | awk '/default/ {print $3}').chomp
    send_mail_port = ENV.has_key?("LOCAL_SEND_MAIL_PORT") ? ENV["LOCAL_SEND_MAIL_PORT"] : "11311"
    client = HTTP::Client.new(send_mail_host, send_mail_port)
    response = client.post("/send_mail_text", body: msg)
    client.close
    @log.info("post-extract send PR build email, id:#{job.id}")
  end

  def build_email_msg(job)
    email_receiver = ENV["PR_BUILD_EMAIL_RECEIVER"]
    email_msg = "
To: #{email_receiver}
Subject: [PR build] #{job.id}: #{job.upstream_repo} PR rpmbuild #{job.job_health}

     PR build result: #{job.job_health}
     upstream_repo: #{job.upstream_repo}
     pr_merge_reference_name: #{job.pr_merge_reference_name}
     upstream_url: #{job.upstream_url} "

    return email_msg
  end
end
