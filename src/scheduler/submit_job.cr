# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def submit_job
    body = @env.request.body.not_nil!.gets_to_end

    job_content = JSON.parse(body)
    job = Job.new(job_content, job_content["id"]?)
    job.submit(job_content["id"]?)
    job["commit_date"] = get_commit_date(job)

    cluster_file = job["cluster"]
    if cluster_file.empty? || cluster_file == "cs-localhost"
      response = submit_single_job(job)
    else
      cluster_config = get_cluster_config(cluster_file,
        job.lkp_initrd_user,
        job.os_arch).not_nil!
      response = submit_cluster_job(job, cluster_config)
    end
  rescue e
    @env.response.status_code = 202
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)

    response = [{
      "job_id"    => "0",
      "message"   => e.to_s,
      "job_state" => "submit",
    }]
  ensure
    response.each do |job_message|
      @log.info(job_message.to_json)
    end
  end

  # return:
  #   success: [{"job_id" => job_id1, "message => "", "job_state" => "submit"}, ...]
  #   failure: [..., {"job_id" => 0, "message" => err_msg, "job_state" => "submit"}]
  def submit_cluster_job(job, cluster_config)
    job_messages = Array(Hash(String, String)).new
    lab = job.lab
    subqueue = job.subqueue
    roles = get_roles(job)

    # collect all job ids
    job_ids = [] of String

    net_id = "192.168.222"
    ip0 = cluster_config["ip0"]?
    if ip0
      ip0 = ip0.as_i
    else
      ip0 = 1
    end

    # steps for each host
    cluster_config["nodes"].as_h.each do |host, config|
      # continue if role in cluster config matches role in job
      next if (config["roles"].as_a.map(&.to_s) & roles).empty?

      host_info = get_host_info(host.to_s)
      job.update(host_info)
      queue = host.to_s
      queue = $1 if queue =~ /(\S+)--[0-9]+$/

      job_id = get_job_id(lab)

      # return when job_id is '0'
      # 2 Questions:
      #   - how to deal with the jobs added to DB prior to this loop
      #   - may consume job before all jobs done
      job_ids << job_id

      # add to job content when multi-test
      job["testbox"] = queue
      job["queue"] = queue
      job.update_tbox_group(queue)
      job["node_roles"] = config["roles"].as_a.join(" ")
      if config["macs"]?
      	direct_macs = config["macs"].as_a
      	direct_ips = [] of String
      	direct_macs.size.times do
        	raise "Host id is greater than 254, host_id: #{ip0}" if ip0 > 254
        	direct_ips << "#{net_id}.#{ip0}"
        	ip0 += 1
      	end
      	job["direct_macs"] = direct_macs.join(" ")
      	job["direct_ips"] = direct_ips.join(" ")
      end

      # multi-machine test requires two network cards
      job["nr_nic"] = "2"
      status, msg = add_job(job, job_id)
      job_id = "0" unless status
      job_messages << {
        "job_id"      => job_id,
        "message"     => msg,
        "job_state"   => "submit",
        "result_root" => "/srv#{job.result_root}",
      }
      return job_messages unless status
    end

    cluster_id = job_ids[0]

    # collect all host states
    cluster_state = Hash(String, Hash(String, String)).new
    job_ids.each do |job_id|
      cluster_state[job_id] = {"state" => ""}
      # will get cluster id according to job id
      @redis.hash_set("sched/id2cluster", job_id, cluster_id)
    end

    @redis.hash_set("sched/cluster_state", cluster_id, cluster_state.to_json)

    return job_messages
  end

  # return:
  #   success: [{"job_id" => job_id, "message" => "", job_state => "submit"}]
  #   failure: [{"job_id" => "0", "message" => err_msg, job_state => "submit"}]
  def submit_single_job(job)
    job_id = get_job_id(job.lab)

    status, msg = add_job(job, job_id)
    job_id = "0" unless status
    return [{
      "job_id"    => job_id,
      "message"   => msg,
      "job_state" => "submit",
      "result_root" => "/srv#{job.result_root}",
    }]
  end

  def add_task(job, job_id)
    task_desc = JSON.parse(%({"domain": "compass-ci", "id": "#{job_id}"}))
    key = "sched/#{job.queue}/ready/#{job.subqueue}/#{job_id}"
    response = @etcd.put(key, task_desc)
    if response
      return true, ""
    else
      return false, "add the job to queue failed: job_id #{job_id}, queue #{key}"
    end
  end

  def get_job_id(lab)
    "#{lab}.#{@redis.get_new_seqno()}"
  end

  def save_secrets(job, job_id)
    return nil unless job["secrets"]?

    @redis.hash_set("id2secrets", job_id, job["secrets"]?.to_json)
    job.delete("secrets")
  end

  def add_job(job, job_id)
    # deal the job fields at first
    save_secrets(job, job_id)
    job.update_id(job_id)

    # save the job to es
    response = @es.set_job_content(job)
    msg = (response["error"]? ? response["error"]["root_cause"] : "")
    return false, msg.to_s if response["error"]?

    # set job_id to ready queue
    add_task(job, job_id)
  end

  def get_cluster_config(cluster_file, lkp_initrd_user, os_arch)
    lkp_src = Jobfile::Operate.prepare_lkp_tests(lkp_initrd_user, os_arch)

    cluster_file_paths = [
      Path.new(CCI_REPOS, LAB_REPO, "cluster", cluster_file),
      Path.new(lkp_src, "cluster", cluster_file)
    ]
    cluster_file_paths.each do |f|
      return YAML.parse(File.read(f)) if File.file?(f)
    end
  end

  def get_roles(job)
    roles = job.hash.keys.map { |key| $1 if key =~ /^if role (.*)/ }
    roles.compact.map(&.strip)
  end

  def get_commit_date(job)
    if (job["upstream_repo"] != "") && (job["upstream_commit"] != "")
      data = JSON.parse(%({"git_repo": "#{job["upstream_repo"]}.git",
                   "git_command": ["git-log", "--pretty=format:%cd", "--date=unix",
                   "#{job["upstream_commit"]}", "-1"]}))
      response = @rgc.git_command(data)
      return response.body if response.status_code == 200
    end

    return nil
  end
end
