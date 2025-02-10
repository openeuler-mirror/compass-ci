# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "./plugins_common"

class Cluster < PluginsCommon
  def handle_job(job)
    cluster_file = job.cluster?
    return [job] unless cluster_file || cluster_file == "cs-localhost"

    cluster_spec = get_cluster_spec_by_job(job) ||
                    get_cluster_spec_by_lab(cluster_file, job.lab)
    jobs = split_cluster_job(job, cluster_spec.as_h)
  end

  def get_cluster_spec_by_job(job)
    return job.cluster_spec?
  end

  # example cluster_spec files:
  # wfg /c/lkp-tests% cat cluster/cs-vm-2p16g
  # ip0: 1
  # nodes:
  #    vm-2p16g-multi-node--1:
  #      roles: [ server ]
  #
  #    vm-2p16g-multi-node--2:
  #      roles: [ client ]
  # wfg /c/lkp-tests% head cluster/ceph-cluster
  # switch: Switch-P12
  # ip0: 1
  # nodes:
  #   taishan200-2280-2s48p-256g--a99:
  #     roles: [ cephnode1 ]
  #     macs: [ "44:67:47:d7:6d:14" ]
  #
  #   taishan200-2280-2s48p-256g--a32:
  #     roles: [ cephnode2 ]
  #     macs: [ "44:67:47:c9:db:38" ]
  def get_cluster_spec_by_lab(cluster_file, lab)
    data = JSON.parse(%({"git_repo": "/gitee.com/compass-ci/lab-#{lab}.git",
                      "git_command": ["git-show", "HEAD:cluster/#{cluster_file}"]}))
    response = @rgc.git_command(data)
    raise "can't get cluster info: #{cluster_file}" unless response.status_code == 200

    return JSON.parse(YAML.parse(response.body).to_json)
  end

  # return:
  def split_cluster_job(job, cluster_spec : Hash(String, JSON::Any))
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

      job_id = Sched.get_job_id
      single_job = Job.new(JSON.parse(job.to_json).as_h, job_id)
      single_job.delete_host_info

      # return when job_id is '0'
      # 2 Questions:
      #   - how to deal with the jobs added to DB prior to this loop
      #   - may consume job before all jobs done
      job_ids << job_id

      # add to job content when multi-test
      single_job.testbox = host
      single_job.update_tbox_group(host)
      single_job.update_kernel_params
      single_job.os_arch = single_job.arch
      single_job.node_roles = spec["roles"].as_a.join(" ")
      if spec["macs"]?
        direct_macs = spec["macs"].as_a
        direct_ips = [] of String
        direct_macs.size.times do
          raise "Host id is greater than 254, host_id: #{ip0}" if ip0 > 254
          direct_ips << "#{net_id}.#{ip0}"
          ip0 += 1
        end
        single_job.direct_macs = direct_macs.join(" ")
        single_job.direct_ips = direct_ips.join(" ")
      end

      # multi-machine test requires two network cards
      single_job.nr_nic = "2"

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
    # TODO: refine this code
    roles = []
    %w(daemon program).each do |k|
      roles += job.hash_hhh[k].each.map { |_, val| if (val) val.as_h["if-role"]?.split(" ")  }
    end
    roles.flatten.compact.map(&.strip)
  end
end
