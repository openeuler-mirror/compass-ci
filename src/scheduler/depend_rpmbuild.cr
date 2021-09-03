# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def depend_rpmbuild
    body = @env.request.body.not_nil!.gets_to_end
    @env.set "log", body

    body = JSON.parse(body).as_h
    return if body["reverse_depends"].to_s.empty?

    job = @es.get_job(body["depend_job_id"].to_s)
    return unless job

    common_info = get_common_info(job)
    common_info.any_merge!(body)

    copy_depend_rpm(common_info)
    create_rpm_cpio(common_info["depend_rpm_dest"])

    submit_reverse_depend_jobs(common_info)
  rescue e
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end

  def submit_reverse_depend_jobs(common_info)
    reverse_depends = common_info["reverse_depends"].to_s.gsub(" ", ",")
    reverse_depends.split(",").each do |package|
      job_content = common_info.any_merge({
        "reverse_depends" => reverse_depends,
        "upstream_repo" => "#{package.to_s[0]}/#{package}/#{package}",
        "depend_rpm_dest" => common_info["depend_rpm_dest"].to_s + "/rpm.cgz",
        "testbox" => "dc-16g",
      })
      spawn Jobfile::Operate.auto_submit_job("rpmbuild-without-arch.yaml", job_content)
    end
  end

  def get_common_info(job)
    common_info = Hash(String, String | JSON::Any).new
    depend_keys = ["commit_id", "upstream_branch", "upstream_repo"]
    depend_keys.each do |k|
      common_info["depend_#{k}"] = job[k]
    end

    need_keys = ["upstream_dir", "os", "os_version", "arch", "docker_image"]
    need_keys.each do |k|
      common_info[k] = job[k]
    end
    common_info
  end

  def copy_depend_rpm(info)
    new_dest = "/srv/tmp#{info["depend_rpm_dest"]}/#{info["depend_job_id"]}"
    info["depend_rpm_dest"] = JSON::Any.new("/srv#{info["depend_rpm_dest"]}")
    return unless ["", "master"].includes?(info["depend_upstream_branch"]?.to_s)

    FileUtils.mkdir_p(new_dest)
    FileUtils.cp_r(info["depend_rpm_dest"].to_s, new_dest)
    info["depend_rpm_dest"] = JSON::Any.new(new_dest)
  end

  def create_rpm_cpio(path)
    cmd = "cd #{path};"
    cmd += "find * | cpio --quiet -o -H newc | gzip > rpm.cgz"
    puts `#{cmd}`
  end
end
