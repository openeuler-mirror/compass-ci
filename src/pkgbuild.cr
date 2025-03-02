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
      build_job = init_pkgbuild_params(job, pkg_name, pkg_params)
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

  def get_ss_pkgbuild_paths(job, upstream_project : String, ss_params : Hash(String, String)) : Array(String)
    pkgname = ss_params["pkgname"]? || upstream_project
    pkgver = ss_params["pkgver"]? || ss_params["commit"]? || ss_params["tag"]? || ss_params["branch"]? || raise "No pkgver/commit/tag/branch in ss.#{upstream_project}"

    # Validate pkgver to prevent directory traversal
    if pkgver.includes?("..")
      raise "Illegal characters .. in pkgver #{pkgver}"
    end
    pkgver = pkgver.gsub(/[^a-zA-Z0-9._-]/, ':')

    config_name = ss_params["config"]? || "defconfig"

    package_names = pkgname.split(" ").map { |pname| "#{pname}.cgz" }
    if upstream_project =~ /^(linux|kernel)/
      dir = job["arch"]
      package_names << "vmlinuz"
    else
      dir = job["rootfs"]
    end

    need_file_store = package_names.map do |pname|
      "ss/pkgbuild/#{upstream_project}/#{dir}/#{config_name}/#{pkgver}/#{pname}"
    end

    if job.hash_array.has_key? "need_file_store"
      job.need_file_store.concat need_file_store
    else
      job.need_file_store = need_file_store
    end
    need_file_store
  end

  # ss:
  #   linux:
  #     fork: linux-next
  #     commit: xxxxx
  # pkg_name = linux
  # pkg_params = {fork => linux-next, commit => xxxx}
  def init_pkgbuild_params(job, pkg_name : String, pkg_params : Hash(String, String)|Nil) : Job?
    if pkg_params
      params = pkg_params.dup
    else
      params = Hash(String, String).new
    end
    params["project"] = pkg_name

    need_file_store = get_ss_pkgbuild_paths(job, pkg_name, params)
    return if need_file_store.all? do |path|
      full_path = File.join(FILE_STORE, path)
      File.exists?(full_path)
    end

    build_job = Job.new(Hash(String, JSON::Any).new)
    build_job.suite = "makepkg"
    build_job.category = "functional"
    build_job.my_account = job.my_account
    build_job.my_email = job.my_email
    build_job.my_name = job.my_name
    build_job.my_token = job.my_token

    docker_image = params.delete("docker_image") || job.docker_image?
    if docker_image
      build_job.docker_image = job.docker_image
      tbox = "dc"
      build_job.os_mount = "container"
    else
      tbox = "vm"
      build_job.os_mount = "initramfs"
    end

    build_job.testbox = tbox
    build_job.tbox_group = tbox

    # kernel builds are not tied to a specific OS, so may choose a more convenient OS
    build_job.os = params.delete("os") || job.os
    build_job.os_version = params.delete("os_version") || job.os_version

    build_job.os_arch = job.os_arch
    build_job.arch = job.arch

    build_job.runtime = "36000"
    build_job.need_memory = "8g"
    build_job.install_os_packages_all = "ruby cpio gzip wget curl git fakeroot coreutils file findutils grep sed bzip2 gcc autoconf automake make patch"
    build_job.need_file_store = Array(String).new
    job.need_file_store.each do |path|
      build_job.need_file_store << path if path =~ /^lkp_src\//
    end

    hh = HashHH.new
    hh["makepkg"] = params
    build_job.hash_hhh["program"] = hh
    build_job.hash_hhh["pp"] = hh.dup
    build_job.hash_hhh["pp"].delete "_upstream_url"
    build_job.hash_hhh["pp"].delete "_upstream_dir"

    return build_job
  end

end
