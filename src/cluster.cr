# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "./plugins_common"

# These are shell lib functions defined in $LKP_SRC
WAIT_PEER_JOBS  = "wait_peer_jobs"
UPDATE_JOB_VARS = "update_job_vars"

class Cluster < PluginsCommon
  def handle_job(job)
    cluster_file = job.cluster?
    return [job] unless cluster_file || cluster_file == "cs-localhost"

    cluster_spec = get_cluster_spec_by_job(job) ||
                    get_cluster_spec_by_lab(cluster_file, job.lab)
    jobs, jobid2roles = split_cluster_job(job, cluster_spec.as_h)
    Cluster.add_cluster_wait_peer(jobs, jobid2roles)
    Cluster.cluster_depends2scripts(jobs, jobid2roles)
    jobs
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

  def split_cluster_job(job, cluster_spec : Hash(String, JSON::Any))
    job_messages = Array(Hash(String, String)).new
    lab = job.lab
    roles = Cluster.get_roles(job)

    # collect all job ids
    jobid2roles = Hash(String, String).new
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
      this_job_roles = spec["roles"].as_a.map(&.to_s) & roles
      next if this_job_roles.empty?

      single_job = Job.new(JSON.parse(job.to_json).as_h)
      single_job.delete_host_info

      jobid2roles[single_job.id] = this_job_roles.join(" ")

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

      jobs << single_job
    end

    return jobs, jobid2roles
  end

  def self.get_roles(job)
    # job.hash_hhh Example:
    # {
    #   "daemon" => {"xxx" => {"if-role" => "server"}},
    #   "program" => {"yyy" => {"if-role" => "client"}}
    # }
    # Return: ["server", "client"]

    roles = [] of String
    %w(daemon program).each do |component|
      job.hash_hhh[component].each do |_, config|
        next unless config
        if role = config["if-role"]?
          roles.concat(role.split(/[, ]+/).map(&.strip))
        end
      end
    end
    roles.uniq
  end

  def self.add_cluster_wait_peer(jobs : Array(Job), jobid2roles : Hash(String, String))
    # Get all job IDs in the cluster
    cluster_job_ids = jobid2roles.keys

    script = "#{UPDATE_JOB_VARS} job_stage=wait_peer ip=$ip direct_macs=\"$direct_macs\" direct_ips=\"$direct_ips\"" \
            "\n#{WAIT_PEER_JOBS} #{cluster_job_ids.map { |jid| "#{jid}.job_stage=wait_peer" }.join(' ')}" \
            "#{UPDATE_JOB_VARS} job_stage=running"

    jobs.each do |job|
      # Store cluster job info
      job.hash_hh["cluster_jobs"] = jobid2roles

      # Process daemon components
      if daemons = job.hash_hhh["daemon"]?
        last_daemon = daemons.keys.last?
        if last_daemon && (config = daemons[last_daemon]?)
          # Add post-script synchronization for daemons
          append_script(config, "post-script", script)
        end
      end

      # Process program components
      if programs = job.hash_hhh["program"]?
        first_program = programs.keys.first?
        if first_program && (config = programs[first_program]?)
          # Add pre-script synchronization for programs
          append_script(config, "pre-script", script)
        end
      end
    end
  end

  # Input Example:
  # jobs: [
  #   Job1 {hash_hhh: {"daemon" => {"xxx" => {"if-role" => "server"}}}},
  #   Job2 {hash_hhh: {"program" => {"yyy" => {"if-role" => "client", "depends-on" => "xxx"}}}}
  #   Job3 {hash_hhh: {"program" => {"yyy" => {"if-role" => "client", "depends-on" => "xxx"}}}}
  # ]
  # jobid2roles: {"job1" => "server", "job2" => "client", "job3" => "client"}
  def self.cluster_depends2scripts(jobs : Array, jobid2roles : Hash(String, String))
    # Step 1: Build role to job ID mapping
    # Example: {"server" => ["job1"], "client" => ["job2", "job3"]}
    role2jobids = Cluster.build_role_mapping(jobid2roles)

    # Step 2: Track bidirectional dependencies
    # Format: { "component@job" => [dependent_components] }
    reverse_deps = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }

    jobs.each do |job|
      # Step 3: Process forward dependencies
      Cluster.process_forward_dependencies(job, jobs, role2jobids, reverse_deps)
    end

    # Step 4: Process reverse dependencies
    Cluster.process_reverse_dependencies(jobs, reverse_deps)
  end

  def self.build_role_mapping(jobid2roles)
    # Input: {"job1" => "server,monitor", "job2" => "client"}
    # Output: {"server" => ["job1"], "monitor" => ["job1"], "client" => ["job2"]}
    role2jobids = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
    jobid2roles.each do |jobid, roles|
      roles.split(/[, ]+/).each { |role| role2jobids[role.strip] << jobid }
    end
    role2jobids
  end

  def self.process_forward_dependencies(job, all_jobs, role2jobids, reverse_deps)
    # Example job component:
    # "program.yyy" => {"if-role" => "client", "depends-on" => "xxx"}
    job.hash_hhh.each do |component_type, components|
      components.each do |component_name, config|
        next unless config
        next unless depends_on = config["depends-on"]?

        # Ignore self-depends
        next if depends_on == component_name

        # Find target components across cluster
        targets = Cluster.find_dependency_targets(depends_on, component_type, all_jobs, role2jobids)
        next if targets.empty?

        # Add pre-script waits and track reverse deps
        add_pre_script_waits(config, targets, component_name)
        track_reverse_dependencies(targets, "#{component_type}.#{component_name}@#{job.id}", reverse_deps)

        # Always add post-script state reporting
        Cluster.add_post_script_report(config, component_name)
      end
    end
  end

  def self.find_dependency_targets(depends_on, dependent_type, all_jobs, role2jobids)
    # Returns array of target component identifiers
    # Example: [{"daemon", "xxx", "job1"}]
    targets = [] of Tuple(String, String, String)

    all_jobs.each do |target_job|
      target_job.hash_hhh.each do |target_component_type, target_components|
        next unless target_config = target_components[depends_on]?

        # Get roles from target component
        roles = target_config["if-role"].to_s.split(/[, ]+/).map(&.strip)

        # Map roles to job IDs
        roles.each do |role|
          role2jobids[role].each do |jid|
            targets << {target_component_type, depends_on, jid}
          end
        end
      end
    end

    targets.uniq
  end

  def self.add_pre_script_waits(config, targets, current_component)
    # Example targets: [{"daemon", "xxx", "job1"}]
    # Adds: "#{WAIT_PEER_JOBS} job1.milestones=xxx-ready"
    waits = targets.map { |t| "#{t[2]}.milestones=#{t[1]}-ready" }
    Cluster.append_script(config, "pre-script", "#{WAIT_PEER_JOBS} #{waits.join(' ')}")
  end

  def self.track_reverse_dependencies(targets, dependent_key, reverse_deps)
    # Example:
    # targets => [{"daemon", "xxx", "job1"}]
    # dependent_key => "program.yyy@job2"
    targets.each do |(t_type, t_name, jid)|
      reverse_key = "#{t_type}.#{t_name}@#{jid}"
      reverse_deps[reverse_key] << dependent_key
    end
  end

  def self.add_post_script_report(config, component_name)
    # Adds: "#{UPDATE_JOB_VARS} milestones=yyy-done"
    Cluster.append_script(config, "post-script", "#{UPDATE_JOB_VARS} milestones=#{component_name}-done")
  end

  def self.process_reverse_dependencies(jobs, reverse_deps)
    # Example reverse_deps entry:
    # "daemon.xxx@job1" => ["program.yyy@job2", "program.yyy@job3"]
    reverse_deps.each do |target_key, dependents|
      # Parse target component info
      target_parts = target_key.split('@')
      target_job_id = target_parts[1]
      target_type, target_name = target_parts[0].split('.', 2)

      # Find target job and component
      target_job = jobs.find(&.id.==(target_job_id))
      next unless target_job

      target_config = target_job.hash_hhh.dig?(target_type, target_name)
      next unless target_config

      # Add state reporting and waits
      Cluster.append_script(target_config, "post-script", "#{UPDATE_JOB_VARS} milestones=#{target_name}-ready")
      Cluster.add_reverse_waits(target_config, dependents)
    end
  end

  def self.add_reverse_waits(config, dependents)
    # Example dependents: ["program.yyy@job2", "program.yyy@job3"]
    # Adds: "#{WAIT_PEER_JOBS} job2.milestones=yyy-done job3.milestones=yyy-done"
    waits = dependents.map do |dep|
      dep_parts = dep.split('@')
      "#{dep_parts[1]}.milestones=#{dep_parts[0].split('.', 2)[1]}-done"
    end
    Cluster.append_script(config, "post-script", "#{WAIT_PEER_JOBS} #{waits.join(' ')}")
  end

  def self.append_script(config, script_type, command)
    return unless config

    # Initialize script type if missing
    config[script_type] ||= ""
    current = config[script_type].to_s

    config[script_type] = current.empty? ? command : "#{current}\n#{command}"
  end
end
