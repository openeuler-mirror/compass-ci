# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def check_admin(account_info)
    return false unless account_info["roles"]?
    return false unless account_info["roles"].to_s.includes?("admin")
    return true
  end

  def check_subqueues(subqueues)
    subqueues.each do |_, subqueue|
      subqueue = subqueue.as_h
      priority = (subqueue["priority"]? ? subqueue["priority"].as_i64 : 9)
      raise "priority needs to be between 0 and 9" if priority < 0 || priority > 9

      weight = (subqueue["weight"]? ? subqueue["weight"].as_i64 : 1)
      raise "weight needs to be between 1 and 100" if weight < 1 || weight > 100

      soft_quota = (subqueue["soft_quota"]? ? subqueue["soft_quota"].as_i64 : 5000)
      hard_quota = (subqueue["hard_quota"]? ? subqueue["hard_quota"].as_i64 : 10000)
      raise "soft_quota has to be less than hard_quota" if soft_quota >= hard_quota
    end
  end

  def delete_subqueue(env)
    body = env.request.body.not_nil!.gets_to_end
    content = JSON.parse(body)

    ["my_email", "subqueue"].each do |key|
      raise "Missing required key: '#{key}'" unless content[key]?
    end

    account_info = @es.get_account(content["my_email"].to_s)
    Utils.check_account_info(content, account_info)
    raise "Only admin can delete subqueue" unless check_admin(account_info)

    @es.delete("subqueue", content["subqueue"].to_s)
  rescue e
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
    { "error_msg" => e.to_s }
  end

  def update_subqueues(env)
    results = Array(Hash(String, String)).new
    body = env.request.body.not_nil!.gets_to_end

    content = JSON.parse(body)
    ["my_email", "subqueues"].each do |key|
      raise "Missing required key: '#{key}'" unless content[key]?
    end

    account_info = @es.get_account(content["my_email"].to_s)
    Utils.check_account_info(content, account_info)
    raise "Only admin can set subqueues" unless check_admin(account_info)

    check_subqueues(content["subqueues"].as_h)

    Subqueue.instance.update(content["subqueues"])
  rescue e
    env.response.status_code = 202
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)

    { "error_msg" => e.to_s }
  end
end
