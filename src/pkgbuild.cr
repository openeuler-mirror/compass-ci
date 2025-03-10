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
      build_job = create_pkgbuild_job(job, pkg_name, pkg_params)
      if build_job
        submit_pkgbuild_job(build_job)
        wait_jobs[build_job.id] = nil
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

  def submit_pkgbuild_job(build_job)
    build_job.init_submit
    Sched.instance.on_job_submit(build_job)
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
    configure_runtime_and_resources(build_job)

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
    build_job
  end

  # Configure Docker or VM settings
  private def configure_environment(build_job, job, params)
    docker_image = params.delete("docker_image") || job.docker_image?
    if docker_image
      build_job.docker_image = job.docker_image
      build_job.testbox = "dc"
      build_job.os_mount = "container"
    else
      build_job.testbox = "vm"
      build_job.os_mount = "initramfs"
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
  private def configure_runtime_and_resources(build_job)
    build_job.runtime = "36000"
    build_job.need_memory = "8g"
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
    build_job.hash_hhh["pp"].delete("_upstream_url")
    build_job.hash_hhh["pp"].delete("_upstream_dir")
  end

end
