# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def set_srpm_info(env)
    # body's data structure:
    # {"type": "create", "job_id": "1", "srpms": [{"os":"centos7", "srpm":"test", "repo_name": "base"}]}
    body = env.request.body.not_nil!.gets_to_end
    body = JSON.parse(body).as_h

    check_params({"srpms" => body["srpms"]?, "job_id" => body["job_id"]?, "type" => body["type"]})
    env.set "log", {"job_id" => body["job_id"], "type" => body["type"]}.to_json
    @log.info("start bulk save srpms")

    bulk_save_srpms(body["srpms"].as_a, body["type"].to_s, body["job_id"].to_s)
  rescue e
    env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end

  def bulk_save_srpms(srpms : Array(JSON::Any), type, job_id)
    payload = Array(Hash(String, Hash(String, Hash(String, JSON::Any) | String))).new
    srpms.each do |srpm_info|
      srpm_info = srpm_info.as_h
      next unless srpm_info["srpm"]?

      id = "#{srpm_info["os"]}--#{srpm_info["srpm"]}"
      payload << { type => {"_index" => "srpm-info", "_id" => id, "doc" => srpm_info }}
    end
    # XXX: string id not supported by manticore, may use "update by query", or Manticore.hash_string_to_i64()
    @es.bulk(payload.to_json, false)
  end

  def check_params(hash)
    missing_params = Array(String).new
    hash.each do |k, v|
      missing_params << k if v.to_s.empty?
    end
    return if missing_params.empty?

    raise "param error: missing #{missing_params}"
  end

end
