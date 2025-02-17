# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "./plugins_common"

# case 1: the dep cgz has exists no need submit pkg job
# case 2: the pkg job has been submitted: XXX
# case 3: need submit pkg job
class PkgBuild < PluginsCommon
  def handle_job(job)
    ss = job.ss?
    return unless ss

    # ss struct:
    # ss:
    #   git:
    #     commit: xxx
    #   mysql:
    #     commit: xxx
    wait_jobs = {} of String => Nil
    ss.each do |pkg_name, pkg_params|
      pbp = init_pkgbuild_params(job, pkg_name, pkg_params)
      cgz, exists = cgz_exists?(pbp)
      # if pkg_name is linux, we should init vmlinuz and modules to job
      update_kernel(job, pbp) if pkg_name == "linux"
      # add cgz to wait job initrd uri
      job.append_initrd_uri(cgz)
      # if cgz exist no need submit pkgbuild job and handle next pkg
      next if exists

      submit_result = submit_pkgbuild_job(job.id, pkg_name, pbp)
      pkgbuild_jobid = submit_result.first_value.not_nil!
      wait_jobs[pkgbuild_jobid] = nil
    end

    unless wait_jobs.empty?
      job.hash_hhh["wait_on"] ||= HashHH.new
      job.hash_hhh["wait_on"].merge! wait_jobs
      job.hash_hhh["wait_options"] ||= HashHH.new
      job.hash_hhh["wait_options"]["fail_fast"] = nil
    end

  rescue ex
    @log.error { "pkgbuild handle job #{ex}" }
    raise ex.to_s
  end

  def update_kernel(job, pbp)
    server_prefix = "#{INITRD_HTTP_PREFIX}/kernel/#{pbp["os_arch"]}/#{pbp.config}/#{pbp.upstream_commit}"
    job.update_kernel_uri("#{server_prefix}/vmlinuz")
    job.update_modules_uri(["#{server_prefix}/modules.cgz"])
  end

  def cgz_exists?(pbp)
    pkg_name = pbp.upstream_repo.split("/")[-1]
    cgz_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
    cgz = "#{SRV_INITRD}/build-pkg/#{pbp["os_mount"]}/#{pbp["os"]}/#{pbp["os_arch"]}/#{pbp["os_version"]}/#{pkg_name}/#{pbp.upstream_commit}.cgz"
    ret_cgz = "#{cgz_http_prefix}#{JobHelper.service_path(cgz, false)}"
    return ret_cgz, true if File.exists?(cgz)
    return ret_cgz, false
  end

  def submit_pkgbuild_job(build_for_job_id, pkg_name, pbp)
    job_yaml = create_pkgbuild_yaml(build_for_job_id, pkg_name, pbp)

    response = %x($LKP_SRC/sbin/submit #{job_yaml})
    @log.info{ "submit pkgbuild job response: #{job_yaml}, #{response}" }

    response = response.split("\n")[-3]
    return {"latest" => $1} if response =~ /latest job id=(.*)/

    id = $1 if response =~ /job id=(.*)/
    raise "submit pkgbuild job response: #{job_yaml}, #{response}" if id == nil || id == "0"
    return {"new" => id}
  end

  # ss:
  #   linux:
  #     fork: linux-next
  #     commit: xxxxx
  # pkg_name = linux
  # pkg_parms = {fork => linux-next, commit => xxxx}
  def init_pkgbuild_params(job, pkg_name, pkg_params)
    params = pkg_params || Hash(String, String).new
    repo_name =  params["fork"]? || pkg_name
    upstream_repo = "#{pkg_name[0]}/#{pkg_name}/#{repo_name}"
    upstream_commit = params["commit"]? || "HEAD"
    upstream_info = get_upstream_info(upstream_repo)
    pkgbuild_repo = "pkgbuild/#{upstream_info["pkgbuild_repo"][0]}"
    pkgbuild_repos = upstream_info["pkgbuild_repo"].as_a
    pkgbuild_repos.each do |repo|
      next unless "#{repo}" =~ /(-git|linux)$/
      pkgbuild_repo = "pkgbuild/#{repo}"
    end

    os = params["os"]? || job.os
    os_version = params["os_version"]? || job.os_version
    testbox = params["testbox"]? || job.testbox

    build_job = JobHash.new(Hash(String, JSON::Any).new)
    build_job.os = os
    build_job.os_version = os_version
    build_job.os_arch = job.os_arch
    build_job.testbox = testbox
    build_job.os_mount = "container"
    build_job.upstream_commit = upstream_commit
    build_job.upstream_repo = upstream_repo
    build_job.pkgbuild_repo = pkgbuild_repo
    build_job.upstream_url = upstream_info["url"][0].as_s
    build_job.upstream_dir = "upstream"
    build_job.pkgbuild_source = upstream_info["pkgbuild_source"][0].as_s if upstream_info["pkgbuild_source"]?
    # update job.id when finished build_job
    build_job.waited = {job.id => "job_health"}
    build_job.services = {
      "SCHED_HOST" => ENV["SCHED_HOST"],
      "SCHED_PORT" => ENV["SCHED_PORT"],
    }
    build_job.runtime = "36000"

    # add user specify build params
    params.each do |k, v|
      # if params key match config*, try link file to pkgbuild config dir
      if k =~ /config.*/
        field_name = k
        filename = File.basename(v)
        #get origin uploaded_file
        ss_upload_filepath = "#{SRV_USER_FILE_UPLOAD}/#{job.suite}/ss.#{pkg_name}.#{field_name}/#{filename}"
        if File.exists?(ss_upload_filepath)
          _pkgbuild_repo = build_job.pkgbuild_repo
          _pkg_name = _pkgbuild_repo.chomp.split('/', remove_empty: true)[-1]
          dest_dir = "#{SRV_USER_FILE_UPLOAD}/pkgbuild/#{pkg_name}/#{field_name}"
          pkg_dest_file = "#{dest_dir}/#{filename}"
          FileUtils.mkdir_p(dest_dir) unless File.exists?(dest_dir)
          #link file
          File.symlink(ss_upload_filepath, pkg_dest_file) unless File.exists?(pkg_dest_file)
        end
        build_job.config = filename
        next
      end
      build_job.hash_any[k] = v
    end

    default = load_default_pkgbuild_yaml

    if build_job.upstream_commit == "HEAD"
      build_job.upstream_commit = get_head_commit(upstream_repo)
    end

    build_job.import2hash(default)
    return build_job
  end

  # input:
  # "t/test-pixz/test-pixz"
  # output:
  # {"url" => ["https://gitee.com/cxl78320/test-pixz"],
  # "pkgbuild_repo" => ["aur-t/test-pixz-git"],
  # "pkgbuild_source" => ["https://github.com/vasi/pixz"]}
  def get_upstream_info(upstream_repo)
    data = JSON.parse(%({"git_repo": "/upstream/u/upstream-repos/upstream-repos.git",
                      "git_command": ["git-show", "HEAD:#{upstream_repo}"]}))
    response = @rgc.git_command(data)
    raise "can't get upstream info: #{upstream_repo}" unless response.status_code == 200

    return JSON.parse(YAML.parse(response.body).to_json)
  end

  def get_head_commit(upstream_repo)
    data = JSON.parse(%({"git_repo": "/upstream/#{upstream_repo}.git",
                      "git_command": ["git-rev-parse", "HEAD"]}))
    response = @rgc.git_command(data)
    raise "can't get head commit: #{upstream_repo}" unless response.status_code == 200

    return response.body
  end

  def create_pkgbuild_yaml(id, pkg_name, build_job)
    job_yaml = "/tmp/yaml/#{id}_#{pkg_name}.yaml"
    dir_name = File.dirname(job_yaml)
    FileUtils.mkdir_p(dir_name) unless File.exists?(dir_name)
    File.open(job_yaml, "w") { |f| f.puts build_job.to_yaml }

    return job_yaml
  end

  def load_default_pkgbuild_yaml
    content = YAML.parse(File.open("#{ENV["LKP_SRC"]}/programs/pkgbuild/jobs/pkgbuild.yaml"))
    content = Hash(String, JSON::Any).from_json(content.to_json)

    return content
  end

end
