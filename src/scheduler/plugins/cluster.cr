# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "./plugins_common"

class Cluster < PluginsCommon
  def handle_job(job)
    cluster_file = job["cluster"]
    return [job] if cluster_file.empty? || cluster_file == "cs-localhost"

    cluster_spec = get_cluster_spec_by_job(job) ||
                    get_cluster_spec_by_lab(cluster_file, job.lab)
    jobs = split_cluster_job(job, cluster_spec)
  end

  def get_cluster_spec_by_job(job)
    return unless job.hash_any.has_key?("cluster_spec")
    return job.hash_any["cluster_spec"]
  end

  def get_cluster_spec_by_lab(cluster_file, lab)
    data = JSON.parse(%({"git_repo": "/gitee.com/wu_fengguang/lab-#{lab}.git",
                      "git_command": ["git-show", "HEAD:cluster/#{cluster_file}"]}))
    response = @rgc.git_command(data)
    raise "can't get cluster info: #{cluster_file}" unless response.status_code == 200

    return JSON.parse(YAML.parse(response.body).to_json)
  end

  # return:
  #   success: [{"job_id" => job_id1, "message => "", "job_state" => "submit"}, ...]
  #   failure: [..., {"job_id" => 0, "message" => err_msg, "job_state" => "submit"}]
  def split_cluster_job(job, cluster_spec)
    job_messages = Array(Hash(String, String)).new
    lab = job.lab
    subqueue = job.subqueue
    roles = get_roles(job)

    # collect all job ids
    job_ids = [] of String
    jobs = [] of Job

    net_id = "192.168.222"
    ip0 = cluster_spec["ip0"]?
    if ip0
      ip0 = ip0.as_i
    else
      ip0 = 1
    end

    # steps for each host
    cluster_spec["nodes"].as_h.each do |host, spec|
      # continue if role in cluster spec matches role in job
      next if (spec["roles"].as_a.map(&.to_s) & roles).empty?

      job_id = @redis.get_job_id(lab)
      single_job = Job.new(JSON.parse(job.dump_to_json).as_h, job_id)
      single_job.delete_host_info

      host_info = Utils.get_host_info(host.to_s)
      single_job.update(host_info)
      queue = host.to_s
      queue = queue = $1 if queue =~ /(\S+)--[0-9]+$/

      # return when job_id is '0'
      # 2 Questions:
      #   - how to deal with the jobs added to DB prior to this loop
      #   - may consume job before all jobs done
      job_ids << job_id

      # add to job content when multi-test
      single_job["testbox"] = queue
      single_job["queue"] = queue
      single_job.update_tbox_group(queue)
      single_job["os_arch"] = host_info["arch"].as_s
      single_job["node_roles"] = spec["roles"].as_a.join(" ")
      if spec["macs"]?
        direct_macs = spec["macs"].as_a
        direct_ips = [] of String
        direct_macs.size.times do
          raise "Host id is greater than 254, host_id: #{ip0}" if ip0 > 254
          direct_ips << "#{net_id}.#{ip0}"
          ip0 += 1
        end
        single_job["direct_macs"] = direct_macs.join(" ")
        single_job["direct_ips"] = direct_ips.join(" ")
      end

      # multi-machine test requires two network cards
      single_job["nr_nic"] = "2"

      single_job.update_id(job_id)
      single_job.set_account_info
      single_job.set_defaults

      jobs << single_job
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
    # XXX
    roles = job.hash_any.keys.map { |key| $1 if key =~ /^if role (.*)/ }
    roles.compact.map(&.strip)
  end
end
