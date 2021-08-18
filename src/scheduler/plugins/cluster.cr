# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "./plugins_common"

class Cluster < PluginsCommon
  def handle_job(job)
    cluster_file = job["cluster"]
    return [job] if cluster_file.empty? || cluster_file == "cs-localhost"

    cluster_config = get_cluster_config(cluster_file, job.lab)
    jobs = split_cluster_job(job, cluster_config)
  end

  def get_cluster_config(cluster_file, lab)
    data = JSON.parse(%({"git_repo": "/gitee.com/wu_fengguang/lab-#{lab}.git",
                      "git_command": ["git-show", "HEAD:cluster/#{cluster_file}"]}))
    response = @rgc.git_command(data)
    raise "can't get cluster info: #{cluster_file}" unless response.status_code == 200

    return YAML.parse(response.body)
  end

  # return:
  #   success: [{"job_id" => job_id1, "message => "", "job_state" => "submit"}, ...]
  #   failure: [..., {"job_id" => 0, "message" => err_msg, "job_state" => "submit"}]
  def split_cluster_job(job, cluster_config)
    job_messages = Array(Hash(String, String)).new
    lab = job.lab
    subqueue = job.subqueue
    roles = get_roles(job)

    # collect all job ids
    job_ids = [] of String
    jobs = [] of Job

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

      host_info = Utils.get_host_info(host.to_s)
      job.update(host_info)
      queue = host.to_s
      queue = queue = $1 if queue =~ /(\S+)--[0-9]+$/

      job_id = @redis.get_job_id(lab)

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

      job.update_id(job_id)

      jobs << Job.new(JSON.parse(job.dump_to_json), job_id)
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

    return jobs
  end

  def get_roles(job)
    roles = job.hash.keys.map { |key| $1 if key =~ /^if role (.*)/ }
    roles.compact.map(&.strip)
  end
end
