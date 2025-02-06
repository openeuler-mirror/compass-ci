# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def submit_install_rpm(env)
    body = env.request.body.not_nil!.gets_to_end
    body = JSON.parse(body).as_h
    return if body["rpm_dest"].to_s.empty?

    job = @es.get_job(body["rpmbuild_job_id"].to_s)
    return unless job

    job_info : Hash(String, String | JSON::Any) = get_job_info(job)
    job_info.any_merge!(body)

    spawn Jobfile::Operate.auto_submit_job("install-rpm.yaml", job_info)
  rescue e
    env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end

  def get_job_info(job)
    job_info = Hash(String, String | JSON::Any).new
    need_keys = %w[os os_version os_arch docker_image]
    need_keys.each do |k|
      job_info[k] = job[k]
    end
    job_info["testbox"] = job.tbox_group
    job_info
  end

  def submit_reverse_depend_jobs(env)
    body = env.request.body.not_nil!.gets_to_end
    env.set "log", body

    body = JSON.parse(body).as_h
    return if body["reverse_depends"].to_s.empty?

    job = @es.get_job(body["depend_job_id"].to_s)
    return unless job

    common_info = get_common_info(job)
    common_info.any_merge!(body)

    submit_reverse_depend_job(common_info)
  rescue e
    env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end

  def submit_reverse_depend_job(common_info)
    reverse_depends = common_info["reverse_depends"].to_s.gsub(" ", ",")
    reverse_depends.split(",").each do |package|
      job_content = common_info.any_merge({
                                            "reverse_depends" => reverse_depends,
                                            "upstream_repo" => "#{package.to_s[0]}/#{package}/#{package}",
                                            "testbox" => "dc-16g"
                                          })
      spawn Jobfile::Operate.auto_submit_job("rpmbuild-without-arch.yaml", job_content)
    end
  end

  def get_common_info(job)
    common_info = Hash(String, String | JSON::Any).new
    depend_keys = %w[commit_id upstream_branch upstream_repo]
    depend_keys.each do |k|
      common_info["depend_#{k}"] = job[k]
    end

    need_keys = %w[upstream_dir os os_version arch docker_image]
    need_keys.each do |k|
      common_info[k] = job[k]
    end
    common_info
  end
end
