# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "singleton"

require "./utils"
require "./constants"
require "./es_client"
require "./json_logger"
require "./etcd_client"
require "../scheduler/redis_client"

class InitReadyQueues
  def initialize
    @es = ES::Client.new
    @log = JSONLogger.new
    @etcd = EtcdClient.new
    @redis = RedisClient.new
    @tbox_type = "dc"
    @ccache_vms = Hash(String, Array(String)).new

    # ready_queues = {vm1:[{..job..}, {..job..}], vm2:[{..job..}, {..job..}]}
    @ready_queues = Hash(String, Hash(String, Array(Hash(String, String)))).new
    @all_tbox = Hash(String, Hash(String, Hash(String, String))).new
    @common_vms = Hash(String, Hash(String, Hash(String, String))).new
    @clone_ready_queues = Hash(String, Array(Hash(String, String))).new
  end

  def self.instance
    Singleton::Of(self).instance
  end

  private def init_ccache_vms
    query = {
      "query": {
        "bool": {
          "must": { "term": {"tbox_type": @tbox_type} },
          "must_not": {"term": { "job_stage": "submit" }}
        }
      },
      "aggs": {
        "group_by_spec_file_name": {
          "terms": { "field": "spec_file_name" },
          "aggs": {
            "sorted_by_submit_time": {
              "top_hits": {
                "_source": ["host_machine"],
                "sort": [{ "submit_time": { "order": "desc" } }],
                "size": 10
              }
            }
          }
        }
      }
    }

    begin
      result = @es.search("jobs", query)
    rescue ex
      @log.warn({
          "message" => "init ccache vms failed: #{ex}",
          "error_message" => ex.inspect_with_backtrace.to_s
        }.to_json)
      return
    end
    return unless result.is_a?(JSON::Any)

    _aggs = result["aggregations"]["group_by_spec_file_name"]["buckets"]
    _aggs.as_a.each do |_agg|
      _tba = [] of String
      _key = _agg["key"]
      _hhs = _agg["sorted_by_submit_time"]["hits"]["hits"]
      _hhs.as_a.each do |_hs|
        next if _hs["_source"].as_h.empty?
        _tb = _hs["_source"]["host_machine"].as_s
        _tba << _tb unless _tba.includes?(_tb)
      end
      @ccache_vms[_key.as_s] = _tba
    end
  end

  private def init_common_vms
    # {aarch64: {vm1:{max_mem: 256}, vm2:{max_mem: 128}, ...}, x86_64: {vm3: {max_mem: 256}, vm4: {max_mem:128}, ...}, ...}
    #@common_vms["aarch64"] = {"test-at1" => {"max_mem" => "256"}}
    #@common_vms["x86_64"] = {"test-xt1"=> {"max_mem" => "256"}, "test-xt2"=> {"max_mem" => "256"}, "test-xt3"=> {"max_mem" => "256"}}
    @common_vms = Utils.parse_vms.clone
  end

  private def init_common_tbox_from_redis
    # {"dc" =>
    #   {"local-test-2" => {"host_name" => "test-2", "is_remote" => "false"},
    #    "local-test-3" => {"host_name" => "test-3", "is_remote" => "false"},
    #    "remote-test-1" => {"host_name" => "test-1", "is_remote" => "true"}},
    #  "vm" => {"remote-test-3" => {"host_name" => "test-3", "is_remote" => "true"}},
    #  "hw" =>
    #   {"local-test-2" => {"host_name" => "test-2", "is_remote" => "false"},
    #    "remote-test-1" => {"host_name" => "test-1", "is_remote" => "true"}}}
    all_keys = @redis.scan_each("/tbox/*")
    @all_tbox = Hash(String, Hash(String, Hash(String, String))).new
    @log.info("init_common_tbox_from_redis #{all_keys}")
    TBOX_TYPES.each do |type|
      all_keys.each do |key|
        next unless key.starts_with?("/tbox/#{type}")
        val = @redis.get(key)
        next unless val
        hval = Hash(String, String).from_json(val)
        @all_tbox[type] ||= Hash(String, Hash(String, String)).new
        @all_tbox[type].merge!({hval["hostname"] => hval})
      end
    end
  end

  private def get_ready_mem(vmx)
    ready_mem = 0
    @clone_ready_queues[vmx] ||= [] of Hash(String, String)
    _jobs = @clone_ready_queues[vmx]
    _jobs.each do |_job|
      ready_mem += _job["memory_minimum"].to_i
    end

    return ready_mem
  end

  private def get_best_vm(vms, need_mem, arch, use_remote_tbox)
    _vms = Array(Hash(String, String)).new
    vms.each do |vmx|
      next unless @all_tbox.has_key?(@tbox_type)
      next unless @all_tbox[@tbox_type].has_key?(vmx)
      next unless @all_tbox[@tbox_type][vmx].has_key?("max_mem")
      _arch = @all_tbox[@tbox_type][vmx]["arch"]
      next if "#{_arch}" != "#{arch}"

      is_remote = @all_tbox[@tbox_type][vmx]["is_remote"]
      next if is_remote == "true" && use_remote_tbox == "n"

      cost_mem = 0
      cost_time = [] of Int32
      kvs = @etcd.range_prefix("/queues/sched/in_process/#{vmx}").kvs
      kvs.each do |kv|
        val = JSON.parse(kv.value.not_nil!).as_h
        mm = val["memory_minimum"]? || 16
        md = val["max_duration"]? || 5

        cost_mem += "#{mm}".to_i
        cost_time << "#{md}".to_i
      end
      ready_mem = get_ready_mem(vmx)

      max_mem = @all_tbox[@tbox_type][vmx]["max_mem"].to_i
      left_mem = max_mem - cost_mem - ready_mem
      if left_mem >= need_mem.to_i
        min_cost_time = cost_time.min? ?  cost_time.min : 5 
        _vms << {"vmx" => vmx, "cost_time" => "#{min_cost_time}", "left_mem" => "#{left_mem}"}
      end
    end

    return nil if _vms.empty?

    _ret = _vms.min_by { |x| [x["cost_time"].to_i, x["left_mem"].to_i] }
    return _ret["vmx"]
  end

  private def init_ready_queues(arch, jobs)
    return unless @all_tbox.has_key?(@tbox_type)

    jobs.each do |_job|
      _select_flag = false
      _sfn = _job["spec_file_name"]?
      _ndm = _job["memory_minimum"]? || "16"
      _use_remote_tbox = _job["use_remote_tbox"]? || "y"
      vmccs = @ccache_vms[_sfn]? || [] of String
      vmx = get_best_vm(vmccs, _ndm, arch, _use_remote_tbox)
      if vmx
        @log.info ("get_best_vm from ccache_wms")
        @clone_ready_queues[vmx] ||= [] of Hash(String, String)
        @clone_ready_queues[vmx] << _job
        next
      end

      type_vms = @all_tbox[@tbox_type]
      arch_vms = type_vms.select do |_, v|
        v["arch"] == arch
      end
      vmx = get_best_vm(arch_vms.keys.shuffle!, _ndm, arch, _use_remote_tbox)
      if vmx
        @log.info ("get_best_vm from common_vms")
        @clone_ready_queues[vmx] ||= [] of Hash(String, String)
        @clone_ready_queues[vmx] << _job
      end
    end
  end

  private def get_priority_weight(my_account, os_project, build_type)
    return 11, 100 if build_type.nil? || build_type.as_s == "single"

    return 7, 50 unless os_project

    if CI_ACCOUNTS.includes?(my_account)
      return 10, 100
    end

    branch_type = nil
    project_info = Utils.get_project_info(PROJECT_JSON, os_project.as_s)
    unless project_info.nil?
      branch_type = project_info["baseos_branch_type"]
    end


    if ADMIN_ACCOUNTS.includes?(my_account)
      return 9, 70 if branch_type.nil?

      if DEV_BRANCHES.includes?(branch_type)
        return 9, 90
      end

      if TTM_BRANCHES.includes?(branch_type)
        return 9, 80
      end

      return 9, 70
    end

    if DEV_BRANCHES.includes?(branch_type) || TTM_BRANCHES.includes?(branch_type)
      return 8, 60
    end

    return 7, 50
  end

  private def get_submit_jobs
    # search es by job_stage=submit, 使用os_arch, my_account, os_project, build_type聚类, sort by memory_minimun
    # "must_not":[{"exists": {"field":"job_health"}}]
    query = {
      "query": {
        "bool": {
          "must": [
            {
              "term": { "job_state": "submit" }
            },
            {
              "term": { "tbox_type": @tbox_type }
            }
          ],
          "must_not": [
            {
              "exists": { "field": "job_health" }
            }
          ]
        }
      },
      "aggs": {
        "group_by_os_arch": {
          "terms": { "field": "os_arch" },
          "aggs": {
            "group_by_my_account": {
              "terms": { "field": "my_account", "size": 1000 },
              "aggs": {
                "sorted_by_submit_time": {
                  "top_hits": {
                    "_source": ["id", "os_arch", "my_account","os_project", "spec_file_name", "memory_minimum", "build_type", "max_duration", "use_remote_tbox"],
                    "sort": [
                      { "submit_time": { "order": "desc" } }
                    ],
                    "size": 100
                  }
                }
              }
            }
          }
        }
      }
    }
    result = @es.search("jobs", query)
    raise result unless result.is_a?(JSON::Any)

    # [{arch:x86_64, jobs:{my_account: [{..id..},{..id..}]}, my_account: [{..id..},{..id..}]},
    #  {arch:aarch64, jobs:{my_account: [{..id..},{..id..}]}, my_account: [{..id..},{..id..}]}]
    ret_aggs = Array(Hash(String, String|Hash(JSON::Any, Array(JSON::Any)))).new

    aggs = result["aggregations"]["group_by_os_arch"]["buckets"]
    aggs.as_a.each do |agg|
      _aggs = Hash(JSON::Any, Array(JSON::Any)).new
      _item_arch = Hash(String, String|Hash(JSON::Any, Array(JSON::Any))).new
      _item_arch["arch"] = agg["key"].as_s
      agg["group_by_my_account"]["buckets"].as_a.each do |my_account|
        key = my_account["key"]
        vals = my_account["sorted_by_submit_time"]["hits"]["hits"]
        vals.as_a.each do |val|
          _aggs[key] = [] of JSON::Any unless _aggs[key]?
          _aggs[key] << val["_source"]
        end
      end
      _item_arch["jobs"] = _aggs
      ret_aggs << _item_arch
    end

    return ret_aggs
  end

  private def set_priority_weight(aggs)
    arr = Array(Hash(String, String)).new
    if aggs.is_a?(String)
      return arr
    end

    aggs.each do |key, vals|
      vals.each do |val|
        p, w = get_priority_weight(key, val["os_project"]?, val["build_type"]?)
        val = val.as_h
        t_val = Hash(String, String).new
        val.each do |k, v|
          t_val[k] = v.as_s
        end
        t_val["priority"] = p.to_s
        t_val["weight"] = w.to_s
        t_val["memory_minimum"] = t_val["memory_minimum"]? || "16"
        arr << t_val
      end
    end

    return arr
  end

  private def compare(dict1, dict2)
    if dict1["priority"] != dict2["priority"]
      dict2["priority"].to_i <=> dict1["priority"].to_i
    else
      dict2["memory_minimum"].to_i <=> dict1["memory_minimum"].to_i
    end
  end

  private def pop_by_weight(jobs)
    _jobs = jobs.clone
    ret_jobs = Array(Hash(String, String)).new
    loop do
      weights = [] of Int32
      _jobs.each do |job|
        weights << job["weight"].to_i unless weights.includes?(job["weight"].to_i)
      end

      index = random_index(weights)
      if index && _jobs
        _index = 0
        _jobs.each do |_job|
          if _job["weight"] == "#{weights[index]}"
            ret_jobs << _jobs.delete_at(_index)
            break
          end
          _index += 1
        end
      end

      if _jobs.empty?
        return ret_jobs
      end
    end
  end

  private def random_index(weights)
    return unless weights.size != 0

    total = 0
    sum = weights.sum
    rand_num = rand(sum)
    0.upto(weights.size - 1 ) do |i|
      total += weights[i]
      if total > rand_num
        return i
      end
    end
  end

  private def sort_jobs_by_weight(arr_sort_by_priority)
    ready_jobs = Array(Hash(String, String)).new
    asbp = arr_sort_by_priority.clone
    if asbp.size == 0
        return ready_jobs
    end

    groups = asbp.group_by {|obj| obj["priority"]}
    gbps = groups.map {|group, objs| objs}
    gbps.each do |gbp|
      ready_jobs += pop_by_weight(gbp)
    end

    return ready_jobs
  end

  def get_ready_queues(tbox_type)
    tbox_type_ready_queues = @ready_queues[tbox_type]? ? @ready_queues[tbox_type] : Hash(String, Array(Hash(String, String))).new

    return tbox_type_ready_queues.clone
  end

  private def init
    begin
      @log.info("timing init ready_queues")
      init_common_tbox_from_redis
      @log.info("all tboxs #{@all_tbox}")
      return if @all_tbox.empty?

      TBOX_TYPES.each do |tbox_type|
        @tbox_type = tbox_type
        init_ccache_vms

        # g_arch_jobs = [{arch:x86_64, jobs:{my_account: [{..id..},{..id..}]}, my_account: [{..id..},{..id..}]}]
        # _arch_jobs = {arch:x86_64, jobs:{my_account: [{..id..},{..id..}]}, my_account: [{..id..},{..id..}]}
        # _p_jobs = [{priority:10, weight: 8, id,...}, {priority:10, weight: 8, id,...}]
        # _w_jobs = [{priority:10, weight: 8, id,...}, {priority:10, weight: 8, id,...}]
        g_arch_jobs = get_submit_jobs
        g_arch_jobs.each do |_arch_jobs|
          _arch = _arch_jobs["arch"]
          _p_jobs = set_priority_weight(_arch_jobs["jobs"])
          _p_jobs.sort!{|dict1, dict2| compare(dict1, dict2)}
          _w_jobs = sort_jobs_by_weight(_p_jobs)
          init_ready_queues(_arch, _w_jobs)
        end
        @ready_queues[@tbox_type] = @clone_ready_queues.clone
        @clone_ready_queues = Hash(String, Array(Hash(String, String))).new
      end
      pp @ready_queues
    rescue ex
      @log.warn({
          "message" => "init ready_queues failed: #{ex}",
          "error_message" => ex.inspect_with_backtrace.to_s
        }.to_json)
    end
  end

  def loop_init
    loop do
      init
      sleep 10
      GC.collect
    end
  end
end
