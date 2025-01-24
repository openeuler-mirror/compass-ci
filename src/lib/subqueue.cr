# SX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "json"
require "singleton"
require "../scheduler/elasticsearch_client"

class Subqueue
  @@default_subqueue = {
    "priority" => 9,
    "weight" => 1,
    "soft_quota" => 5000,
    "hard_quota" => 10000
  }

  def self.instance
    Singleton::Of(self).instance
  end

  def initialize
    @es = Elasticsearch::Client.new
    @priority = Hash(String, String).new
    @subqueue2prio_weight = Hash(String, JSON::Any).new
    @priority2subqueue = Hash(Int64, Set(String)).new
    init_from_es
  end

  def get_weight(subqueue)
    subqueue2prio_weight = (@subqueue2prio_weight[subqueue]? || @@default_subqueue)
    weight = (subqueue2prio_weight["weight"]? || 1).to_s
    return weight.to_i64
  end

  def get_priority2subqueue(i)
    @priority2subqueue[i]? || Set(String).new
  end

  def create_subqueue2prio_weight
    subqueue2prio_weight = Hash(String, JSON::Any).new
    get_subqueues.each do |subqueue|
      subqueue2prio_weight[subqueue["_id"].to_s] = subqueue["_source"]
    end
    subqueue2prio_weight
  end

  def get_subqueue_info(subqueue)
    @subqueue2prio_weight[subqueue]? || @@default_subqueue
  end

  def get_subqueues
    @es.search("subqueue", Hash(String, String).new)
  end

  def create_priority2subqueue(subqueue2prio_weight)
    priority2subqueue = Hash(Int64, Set(String)).new
    subqueue2prio_weight.each do |k, v|
      priority = v["priority"].as_i64
      if priority2subqueue.has_key?(priority)
        priority2subqueue[priority].add(k)
        next
      end
      priority2subqueue[priority] = [k].to_set
    end
    priority2subqueue
  end

  def init_from_es
    subqueue2prio_weight = create_subqueue2prio_weight
    priority2subqueue = create_priority2subqueue(subqueue2prio_weight)
    @subqueue2prio_weight = subqueue2prio_weight
    @priority2subqueue = priority2subqueue
  end

  def timing_refresh_from_es
    while true
      sleep(1800.seconds)
      init_from_es
    end
  end

  def update(subqueues : JSON::Any)
    subqueues.as_h.each do |key, content|
      update_one_subqueue(key, content)
    end
  end

  def update_one_subqueue(subqueue, content)
    @es.create_subqueue(content, subqueue)
    init_from_es
  end
end
