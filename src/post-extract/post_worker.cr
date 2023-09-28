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
      job = @es.get_job_content(job_id)
      
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
      sleep(10)
    ensure
      @etcd.close
    end
  end

  def send_workflow_event(job_id, job)
    workflow_exec_id = job["workflow_exec_id"]?.to_s
    return if workflow_exec_id.nil? || workflow_exec_id.empty?

    post_extract_queue = "/events/post_extract/#{workflow_exec_id}/#{job_id}"
    @etcd.put(post_extract_queue, job.to_json)
  end

  def get_pr_result(job)
    return if !(job.[]?("pr_merge_reference_name") && job.[]?("upstream_dir") && job["upstream_dir"] == "openeuler")

    send_email(job)
  end

  def send_email(job)
    msg = build_email_msg(job)
    send_mail_host = %x(/sbin/ip route | awk '/default/ {print $3}').chomp
    send_mail_port = ENV.has_key?("LOCAL_SEND_MAIL_PORT") ? ENV["LOCAL_SEND_MAIL_PORT"] : "11311"
    client = HTTP::Client.new(send_mail_host, send_mail_port)
    response = client.post("/send_mail_text", body: msg)
    client.close
    @log.info("post-extract send PR build email, id:#{job["id"]}")
  end

  def build_email_msg(job)
    email_receiver = ENV["PR_BUILD_EMAIL_RECEIVER"]
    email_msg = "
To: #{email_receiver}
Subject: [PR build] #{job["id"]}: #{job["upstream_repo"]} PR rpmbuild #{job["job_health"]}

     PR build result: #{job["job_health"]}
     upstream_repo: #{job["upstream_repo"]}
     pr_merge_reference_name: #{job["pr_merge_reference_name"]}
     upstream_url: #{job["upstream_url"]} "

    return email_msg
  end
end
