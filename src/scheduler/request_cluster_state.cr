# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  # Return response according to different request states.
  # all request states:
  #     wait_ready | abort | failed | finished | wait_finish |
  #     write_state | roles_ip
  def request_cluster_state
    request_state = @env.params.query["state"]
    job_id = @env.params.query["job_id"]
    cluster_id = @redis.hash_get("sched/id2cluster", job_id).not_nil!
    cluster_state = ""

    states = {"abort"       => "abort",
              "started"     => "start",
              "finished"    => "finish",
              "failed"      => "abort",
              "wait_ready"  => "ready",
              "wait_finish" => "finish"}

    case request_state
    when "abort", "started", "failed"
      # update node state only
      update_cluster_state(cluster_id, job_id, {"state" => states[request_state]})
    when "wait_ready"
      update_cluster_state(cluster_id, job_id, {"state" => states[request_state]})
      @@block_helper.block_until_finished(cluster_id) {
        cluster_state = sync_cluster_state(cluster_id, job_id, states[request_state])
        cluster_state == "ready" || cluster_state == "abort"
      }

      return cluster_state
    when "wait_finish", "finished"
      update_cluster_state(cluster_id, job_id, {"state" => states[request_state]})
      while 1
        sleep(10)
        cluster_state = sync_cluster_state(cluster_id, job_id, states[request_state])
        break if (cluster_state == "finish" || cluster_state == "abort")
      end

      return cluster_state
    when "write_state"
      node_roles = @env.params.query["node_roles"]
      node_ip = @env.params.query["ip"]
      direct_ips = @env.params.query["direct_ips"]
      direct_macs = @env.params.query["direct_macs"]

      job_info = {"roles"       => node_roles,
                  "ip"          => node_ip,
                  "direct_ips"  => direct_ips,
                  "direct_macs" => direct_macs}
      update_cluster_state(cluster_id, job_id, job_info)
    when "roles_ip"
      cluster_state = get_cluster_state(cluster_id)
      roles_ip = [] of String

      cluster_state.each_value do |host_state|
        roles = host_state["roles"]
        direct_ips = host_state["direct_ips"]
        node_ip = host_state["ip"]
        roles_ip << "direct_#{roles}_ips=#{direct_ips}"
        roles_ip << "#{roles}=#{node_ip}"
      end

      return roles_ip.join('\n')
    end

    # show cluster state
    return @redis.hash_get("sched/cluster_state", cluster_id)
  rescue e
    @log.warn(e)
  end

  # node_state: "finish" | "ready"
  def sync_cluster_state(cluster_id, job_id, node_state)
    cluster_state = get_cluster_state(cluster_id)
    cluster_state.each_value do |host_state|
      state = host_state["state"]
      return "abort" if state == "abort"
    end

    cluster_state.each_value do |host_state|
      state = host_state["state"]
      next if "#{state}" == "#{node_state}"
      return "retry"
    end

    # cluster state is node state when all nodes are normal
    return node_state
  end

  # return:
  #     Hash(String, Hash(String, String))
  def get_cluster_state(cluster_id)
    cluster_state = @redis.hash_get("sched/cluster_state", cluster_id)
    if cluster_state
      cluster_state = Hash(String, Hash(String, String)).from_json(cluster_state)
    else
      cluster_state = Hash(String, Hash(String, String)).new
    end
    return cluster_state
  end

  # Update job info according to cluster id.
  def update_cluster_state(cluster_id, job_id, job_info : Hash(String, String))
    cluster_state = get_cluster_state(cluster_id)
    if cluster_state[job_id]?
      cluster_state[job_id].merge!(job_info)
      @redis.hash_set("sched/cluster_state", cluster_id, cluster_state.to_json)
    end
  end

  # get the node state of role from cluster_state
  private def get_role_state(cluster_id, role)
    cluster_state = get_cluster_state(cluster_id)
    cluster_state.each_value do |role_state|
      return role_state if role_state["roles"] == role
    end
  end
end
