# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def submit_job(env : HTTP::Server::Context)
    body = env.request.body.not_nil!.gets_to_end

    job_content = JSON.parse(body)
    job = Job.new(job_content, job_content["id"]?)
    job["commit_date"] = get_commit_date(job)

    # it is not a cluster job if cluster field is empty or
    # field's prefix is 'cs-localhost'
    cluster_file = job["cluster"]
    if cluster_file.empty? || cluster_file.starts_with?("cs-localhost")
      return submit_single_job(job)
    else
      cluster_config = get_cluster_config(cluster_file,
        job.lkp_initrd_user,
        job.os_arch)
      return submit_cluster_job(job, cluster_config)
    end
  rescue ex
    puts ex.inspect_with_backtrace
    return [{
      "job_id"    => "0",
      "message"   => ex.to_s,
      "job_state" => "submit",
    }]
  end

  # return:
  #   success: [{"job_id" => job_id1, "message => "", "job_state" => "submit"}, ...]
  #   failure: [..., {"job_id" => 0, "message" => err_msg, "job_state" => "submit"}]
  def submit_cluster_job(job, cluster_config)
    job_messages = Array(Hash(String, String)).new
    lab = job.lab

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
      tbox_group = host.to_s
      job_id = add_task(tbox_group, lab)

      # return when job_id is '0'
      # 2 Questions:
      #   - how to deal with the jobs added to DB prior to this loop
      #   - may consume job before all jobs done
      return job_messages << {
        "job_id"    => "0",
        "message"   => "add task queue sched/#{tbox_group} failed",
        "job_state" => "submit",
      } unless job_id

      job_ids << job_id

      # add to job content when multi-test
      job["testbox"] = tbox_group
      job.update_tbox_group(tbox_group)
      job["node_roles"] = config["roles"].as_a.join(" ")
      direct_macs = config["macs"].as_a
      direct_ips = [] of String
      direct_macs.size.times do
        raise "Host id is greater than 254, host_id: #{ip0}" if ip0 > 254
        direct_ips << "#{net_id}.#{ip0}"
        ip0 += 1
      end
      job["direct_macs"] = direct_macs.join(" ")
      job["direct_ips"] = direct_ips.join(" ")

      response = add_job(job, job_id)
      message = (response["error"]? ? response["error"]["root_cause"] : "")
      job_messages << {
        "job_id"      => job_id,
        "message"     => message.to_s,
        "job_state"   => "submit",
        "result_root" => "/srv#{job.result_root}",
      }
      return job_messages if response["error"]?
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
    queue = job.queue
    return [{
      "job_id"    => "0",
      "message"   => "get queue failed",
      "job_state" => "submit",
    }] unless queue

    # only single job will has "idle job" and "execute rate limiter"
    if job["idle_job"].empty?
      queue += "#{job.get_uuid_tag}"
    else
      queue = "#{queue}/idle"
    end

    job_id = add_task(queue, job.lab)
    return [{
      "job_id"    => "0",
      "message"   => "add task queue sched/#{queue} failed",
      "job_state" => "submit",
    }] unless job_id

    response = add_job(job, job_id)
    message = (response["error"]? ? response["error"]["root_cause"] : "")

    return [{
      "job_id"      => job_id,
      "message"     => message.to_s,
      "job_state"   => "submit",
      "result_root" => "/srv#{job.result_root}",
    }]
  end

  # return job_id
  def add_task(queue, lab)
    task_desc = JSON.parse(%({"domain": "compass-ci", "lab": "#{lab}"}))
    response = @task_queue.add_task("sched/#{queue}", task_desc)
    JSON.parse(response[1].to_json)["id"].to_s if response[0] == 200
  end

  # add job content to es and return a response
  def add_job(job, job_id)
    job.update_id(job_id)
    @es.set_job_content(job)
  end

  # get cluster config using own lkp_src cluster file,
  # a hash type will be returned
  def get_cluster_config(cluster_file, lkp_initrd_user, os_arch)
    lkp_src = Jobfile::Operate.prepare_lkp_tests(lkp_initrd_user, os_arch)
    cluster_file_path = Path.new(lkp_src, "cluster", cluster_file)
    return YAML.parse(File.read(cluster_file_path))
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
