# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "./plugins_common"
require "set"

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
      build_job = create_pkgbuild_job(job, pkg_name, pkg_params)

      if build_job
        build_job.init_submit
        limit = 3
        skip_submit = false

        submitted_jobs = find_existing_job(build_job, limit)

        submitted_jobs.each do |select_job|
          select_job_id = select_job["id"].to_s
          select_job_stage = select_job["job_stage"].to_s
          select_job_health = select_job["job_health"].to_s

          # build job running or submitted, need add to wait_jobs, then handle next ss build job
          if select_job_stage != "finish"
            @log.info { "Found existing submit job #{select_job_id} for #{pkg_name}, adding to wait_jobs" }
            wait_jobs[select_job_id] = nil
            skip_submit = true
            break
          # build job run success, don't add to wait_jobs, should handle next ss build job
          elsif select_job_health == "success"
            @log.info { "Found success job #{select_job_id} for #{pkg_name}, handle next ss build job" }
            skip_submit = true
            break
          end
        end

        if skip_submit
          next
        end

        if submitted_jobs.size < limit
          Sched.instance.on_job_submit(build_job)
          @log.info { "submit job #{build_job.id} for #{pkg_name}, adding to wait_jobs" }
          wait_jobs[build_job.id] = nil
        else
          raise "the all_params_md5: #{build_job.all_params_md5} job build failed, build times: #{submitted_jobs.size}"
        end
      end
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

  private def find_existing_job(build_job : Job, limit : Int)
    query_submitted = {
      "all_params_md5" => "#{build_job.all_params_md5}"
    }
    custom_condition = "LIMIT #{limit}"

    Sched.instance.es.select("jobs", query_submitted, "id, job_stage, job_health", custom_condition)
  end

  # ss:
  #   linux:
  #     fork: linux-next
  #     commit: xxxxx
  # pkg_name = linux
  # pkg_params = {fork => linux-next, commit => xxxx}
  def create_pkgbuild_job(job : Job, pkg_name : String, pkg_params : Hash(String, String)?) : Job?
    return unless job.hash_array.has_key?("need_file_store")

    # Check if any required files are missing in the file store
    return unless any_missing_files?(job, pkg_name)

    # Initialize build parameters
    params = pkg_params ? pkg_params.dup : Hash(String, String).new
    params["project"] = pkg_name

    # Create and configure the build job
    build_job = create_build_job(job, params)

    # Configure Docker or VM settings
    configure_environment(build_job, job, params)

    # Set OS and architecture details
    configure_os_and_arch(build_job, job, params)

    # Set runtime and resource requirements
    configure_runtime_and_resources(build_job, params)

    # Copy relevant file store paths
    copy_file_store_paths(build_job, job)

    # Configure program and parameters
    configure_program_and_pp(build_job, params)

    build_job
  end

  # Check if any required files are missing in the file store
  private def any_missing_files?(job, pkg_name) : Bool
    job.need_file_store.any? do |path|
      next false unless path.starts_with?("ss/pkgbuild/#{pkg_name}/")
      if File.exists?(File.join(FILE_STORE, path))
        next false
      elsif !IS_ROOT_USER && File.exists?(File.join(GLOBAL_FILE_STORE, path))
        next false
      else
        next true
      end
    end
  end

  # Create and configure the build job
  private def create_build_job(job, params) : Job
    build_job = Job.new(Hash(String, JSON::Any).new)

    build_job.suite = "makepkg"
    build_job.category = "functional"

    build_job.my_account = job.my_account
    build_job.my_email = job.my_email
    build_job.my_name = job.my_name
    build_job.my_token = job.my_token

    if (url = params["_url"]?) && (dir = Utils.url2cache_dir(url))
      build_job.cache_dirs = [ dir ]
    else
      # Fall back to a cache-indicator (0--*). It'll work fine (reclaimed
      # at the same time) as long as we keep its mtime in sync with the
      # real cache dir/file, which is done in
      # - $LKP_SRC/lib/job.sh touch_cache_indicator()
      # - $LKP_SRC/lib/git.sh git_update_cache()
      build_job.cache_dirs = [ "0--makepkg/" + params["project"] ]
    end

    build_job
  end

  # Configure Docker or VM settings
  private def configure_environment(build_job, job, params)
    testbox = params.delete("testbox")
    if testbox
      hw = Hash(String, String).new
      build_job.testbox = testbox
      if testbox.starts_with?("dc")
        build_job.docker_image = params.delete("docker_image") || "openeuler/openeuler:24.03"
        build_job.os_mount = "container"
        nr_cpu = params.delete("nr_cpu") || "1"
        memory = params.delete("memory") || "8g"
      else
        build_job.os_mount = params.delete("os_mount") || "initramfs"
        nr_cpu = params.delete("nr_cpu")
        memory = params.delete("memory")
      end
      hw["nr_cpu"] = nr_cpu if nr_cpu
      hw["memory"] = memory if memory
      build_job.hash_hh["hw"] = hw unless hw.empty?
    else
      docker_image = params.delete("docker_image") || job.docker_image?
      if docker_image
        build_job.docker_image = job.docker_image
        build_job.testbox = "dc"
        build_job.os_mount = "container"
      else
        build_job.testbox = "vm"
        build_job.os_mount = "initramfs"
      end
    end
    build_job.tbox_group = build_job.testbox
  end

  # Set OS and architecture details
  private def configure_os_and_arch(build_job, job, params)
    # kernel builds are not tied to a specific OS, so may choose a more convenient OS
    build_job.os = params.delete("os") || job.os
    build_job.os_version = params.delete("os_version") || job.os_version

    build_job.os_arch = job.os_arch
    build_job.arch = job.arch
  end

  # Set runtime and resource requirements
  private def configure_runtime_and_resources(build_job, params)
    build_job.runtime = params.delete("runtime") || "36000"
    build_job.install_os_packages_all = "ruby cpio gzip wget curl git fakeroot coreutils file findutils grep sed bzip2 gcc autoconf automake make patch"
  end

  # Copy relevant file store paths
  private def copy_file_store_paths(build_job, job)
    build_job.need_file_store = Array(String).new
    job.need_file_store.each do |path|
      build_job.need_file_store << path if path =~ /^lkp_src\//
    end
  end

  # Configure program and parameters
  private def configure_program_and_pp(build_job, params)
    hh = HashHH.new
    hh["makepkg"] = params
    build_job.hash_hhh["program"] = hh
    build_job.hash_hhh["pp"] = hh.dup
    build_job.hash_hhh["pp"].delete("_url")
    build_job.hash_hhh["pp"].delete("pkgname")
  end

end
