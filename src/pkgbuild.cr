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
      build_job, exists = init_pkgbuild_params(job, pkg_name, pkg_params)
      # if cgz exist no need submit pkgbuild job and handle next pkg
      next if exists

      id = submit_pkgbuild_job(build_job)
      wait_jobs[id] = nil
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

  def update_kernel(job, build_job, program_pkgbuild)
    server_prefix = "#{INITRD_HTTP_PREFIX}/kernel/#{build_job["os_arch"]}/#{program_pkgbuild["config"]}/#{program_pkgbuild["upstream_commit"]}"
    job.update_kernel_uri("#{server_prefix}/vmlinuz")
    job.update_modules_uri(["#{server_prefix}/modules.cgz"])
  end

  def cgz_exists?(build_job, program_pkgbuild)
    pkg_name = program_pkgbuild["upstream_repo"].split("/")[-1]
    cgz_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
    cgz = "#{SRV_INITRD}/build-pkg/#{build_job["os_mount"]}/#{build_job["os"]}/#{build_job["os_arch"]}/#{build_job["os_version"]}/#{pkg_name}/#{program_pkgbuild["upstream_commit"]}.cgz"
    ret_cgz = "#{cgz_http_prefix}#{JobHelper.service_path(cgz, false)}"
    return ret_cgz, true if File.exists?(cgz)
    return ret_cgz, false
  end

  def submit_pkgbuild_job(build_job)
    id = Sched.get_job_id
    build_job.update_id(id)
    Sched.instance.on_job_submit(build_job)
    id
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
    if upstream_commit == "HEAD"
      upstream_commit = get_head_commit(upstream_repo)
    end

    upstream_info = get_upstream_info(upstream_repo)
    pkgbuild_repo = "pkgbuild/#{upstream_info["pkgbuild_repo"][0]}"
    pkgbuild_repos = upstream_info["pkgbuild_repo"].as_a
    pkgbuild_repos.each do |repo|
      next unless "#{repo}" =~ /(-git|linux)$/
      pkgbuild_repo = "pkgbuild/#{repo}"
    end

    os = params["os"]? || job.os
    os_version = params["os_version"]? || job.os_version
    testbox = params["testbox"]? || "dc"

    build_job = Job.new(Hash(String, JSON::Any).new, nil)
    build_job.suite = "pkgbuild"
    build_job.category = "functional"
    build_job.my_account = job.my_account
    build_job.os = os
    build_job.os_mount = "container"
    build_job.os_version = os_version
    build_job.os_arch = job.os_arch
    build_job.arch = job.arch
    build_job.testbox = testbox
    build_job.runtime = "36000"
    build_job.need_memory = "16g"
    build_job.install_os_packages_all = "wget curl git fakeroot coreutils file findutils grep sed gzip bzip2 gcc autoconf automake make patch"

    program_pkgbuild = {
      "upstream_commit"     => upstream_commit,
      "upstream_repo"       => upstream_repo,
      "pkgbuild_repo"       => pkgbuild_repo,
      "_upstream_url"       => upstream_info["url"][0].as_s,
      "_upstream_dir"       => "upstream",
    }
    program_pkgbuild["_pkgbuild_source"] = upstream_info["pkgbuild_source"][0].as_s if upstream_info["pkgbuild_source"]?

    # add user specify build params
    params.each do |k, v|
      # if params key match config*, try link file to pkgbuild config dir
      if k =~ /config.*/
        field_name = k
        filename = File.basename(v)
        #get origin uploaded_file
        ss_upload_filepath = "#{SRV_USER_FILE_UPLOAD}/#{job.suite}/ss.#{pkg_name}.#{field_name}/#{filename}"
        if File.exists?(ss_upload_filepath)
          pkg_name = pkgbuild_repo.chomp.split('/', remove_empty: true)[-1]
          dest_dir = "#{SRV_USER_FILE_UPLOAD}/pkgbuild/#{pkg_name}/#{field_name}"
          pkg_dest_file = "#{dest_dir}/#{filename}"
          FileUtils.mkdir_p(dest_dir) unless File.exists?(dest_dir)
          #link file
          File.symlink(ss_upload_filepath, pkg_dest_file) unless File.exists?(pkg_dest_file)
        end
        program_pkgbuild["config"] = filename
        next
      end
      program_pkgbuild[k] = v
    end

    hh = HashHH.new
    hh["pkgbuild"] = program_pkgbuild
    build_job.hash_hhh["program"] = hh
    build_job.hash_hhh["pp"] = hh.dup
    build_job.hash_hhh["pp"].delete "_upstream_url"
    build_job.hash_hhh["pp"].delete "_upstream_dir"

    cgz, exists = cgz_exists?(build_job, program_pkgbuild)
    # if pkg_name is linux, we should init vmlinuz and modules to job
    update_kernel(job, build_job, program_pkgbuild) if pkg_name == "linux"
    # add cgz to wait job initrd uri
    job.append_initrd_uri(cgz)

    return build_job, exists
  end

  # input:
  # "t/test-pixz/test-pixz"
  # output:
  # {"url" => ["https://gitee.com/cxl78320/test-pixz"],
  # "pkgbuild_repo" => ["aur-t/test-pixz-git"],
  # "pkgbuild_source" => ["https://github.com/vasi/pixz"]}
  def get_upstream_info(upstream_repo)
    if upstream_repo == "l/linux/linux"
			# mock version for quick test w/o git-daemon
			return JSON.parse({"url" => ["https://mirrors.tuna.tsinghua.edu.cn/git/linux.git"],
											"pkgbuild_repo" => ["packages//linux/trunk", "aur-l/linux"],
											"pkgbuild_source" => ["https://git.archlinux.org/linux"]}.to_json)
    elsif upstream_repo == "t/test-pixz/test-pixz"
			return JSON.parse({"url" => ["https://gitee.com/cxl78320/test-pixz"],
											"pkgbuild_repo" => ["aur-t/test-pixz-git"],
											"pkgbuild_source" => ["https://github.com/vasi/pixz"]}.to_json)
		else
			data = JSON.parse(%({"git_repo": "/upstream/u/upstream-repos/upstream-repos.git",
											"git_command": ["git-show", "HEAD:#{upstream_repo}"]}))
			response = @rgc.git_command(data)
			raise "can't get upstream info: #{upstream_repo}" unless response.status_code == 200

			return JSON.parse(YAML.parse(response.body).to_json)
		end
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

end
