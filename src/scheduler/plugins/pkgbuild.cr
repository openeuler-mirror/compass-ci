# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
require "./plugins_common"

# case 1: the dep cgz has exists no need submit pkg job
# case 2: the pkg job has been submitted:
#   case 1: waited job in etcd, add wait job id to waited job waited field
#   case 2: waited job not in etcd, update wait job current from es by waited finally state
# case 3: need submit pkg job
class PkgBuild < PluginsCommon
  def handle_job(job)
    ss = job.ss?
    return unless ss

    # job id has been init in init_job_id function
    wait_id = job.id
    # add job to wait queue for waited job update current
    wait_queue = add_job2queue(job)

    # ss struct:
    # ss:
    #   git:
    #     commit: xxx
    #   mysql:
    #     commit: xxx
    ss.each do |pkg_name, pkg_params|
      pbp = init_pkgbuild_params(job, pkg_name, pkg_params)
      cgz, exists = cgz_exists?(pbp)
      # if pkg_name is linux, we should init vmlinuz and modules to job
      update_kernel(job, pbp) if pkg_name == "linux"
      # add cgz to wait job initrd uri
      job.append_initrd_uri(cgz)
      # if cgz exist no need submit pkgbuild job and handle next pkg
      next if exists

      submit_result = submit_pkgbuild_job(wait_id, pkg_name, pbp)
      waited_id = submit_result.first_value.not_nil!
      # the same pkg job has been submitted
      ret = add_waited2job(waited_id, {wait_id => "job_health"}) if submit_result.has_key?("latest")
      raise "add waited to id2job failed, waited_job_id=#{waited_id}" if ret == -1

      # cant find id2job in etcd if ret == 0, need update wait current from es
      update_wait_current_from_es(job, waited_id, "job_health") if ret == 0

      add_desired2queue(job, {waited_id => JSON.parse({"job_health" => "success"}.to_json)})
    end

    save_job2es(job)
    save_job2etcd(job)
    if job.wait?
      @log.info("#{job.id}, #{job.wait}")
    else
      # if no wait field, move wait to ready queue
      wait2ready(wait_queue)
    end
  rescue ex
    @log.error("pkgbuild handle job #{ex}")
    wait2die(wait_queue) if wait_queue
    raise ex.to_s
  end

  def add_job2queue(job)
    job.added_by = ["pkgbuild"]
    key = "sched/wait/#{job.queue}/#{job.subqueue}/#{job.id}"
    value = Hash(String, JSON::Any).new
    value["id"] = JSON::Any.new(job.id)

    if job.waited?
      value["waited"] = JSON.parse(job.waited.to_json)
    end

    response = @etcd.put(key, value.to_json)
    raise "add the job to queue failed: id #{job.id}, queue #{key}" unless response
    @log.info("etcd succcess put id #{job.id}, queue #{key}")

    return key
  end

  def update_kernel(job, pbp)
    server_prefix = "#{INITRD_HTTP_PREFIX}/kernel/#{pbp["os_arch"]}/#{pbp.config}/#{pbp.upstream_commit}"
    job.update_kernel_uri("#{server_prefix}/vmlinuz")
    job.update_modules_uri("#{server_prefix}/modules.cgz")
  end

  def delete_job4queue(job)
    key = "sched/wait/#{job.queue}/#{job.subqueue}/#{job.id}"
    @etcd.delete(key)
  end

  def cgz_exists?(pbp)
    pkg_name = pbp.upstream_repo.split("/")[-1]
    cgz_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
    cgz = "#{SRV_INITRD}/build-pkg/#{pbp["os_mount"]}/#{pbp["os"]}/#{pbp["os_arch"]}/#{pbp["os_version"]}/#{pkg_name}/#{pbp.upstream_commit}.cgz"
    ret_cgz = "#{cgz_http_prefix}#{JobHelper.service_path(cgz, false)}"
    return ret_cgz, true if File.exists?(cgz)
    return ret_cgz, false
  end

  def submit_pkgbuild_job(wait_id, pkg_name, pbp)
    job_yaml = create_pkgbuild_yaml(wait_id, pkg_name, pbp)

    response = %x($LKP_SRC/sbin/submit #{job_yaml})
    @log.info("submit pkgbuild job response: #{job_yaml}, #{response}")

    response = response.split("\n")[-2]
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
    upstream_info = get_upstream_info(upstream_repo)
    pkgbuild_repo = "pkgbuild/#{upstream_info["pkgbuild_repo"][0]}"
    pkgbuild_repos = upstream_info["pkgbuild_repo"].as_a
    pkgbuild_repos.each do |repo|
      next unless "#{repo}" =~ /(-git|linux)$/
      pkgbuild_repo = "pkgbuild/#{repo}"
    end
    # now support openeuler:20.03-fat and archlinux:02-23-fat
    os_version = "#{job.os_version}".split("-pre")[0].split("-fat")[0]
    docker_image = "#{job.os}:#{os_version}-fat"
    if pkg_name == "linux"
      testbox = "dc-32g"
    else
      testbox = "dc-16g"
    end

    content = JobHash.new(Hash(String, JSON::Any).new)
    content.os = job.os
    content.os_version = "#{os_version}-fat"
    content.os_arch = job.os_arch
    content.testbox = testbox
    content.os_mount = "container"
    content.docker_image = docker_image
    content.commit = "HEAD"
    content.upstream_repo = upstream_repo
    content.pkgbuild_repo = pkgbuild_repo
    content.upstream_url = upstream_info["url"][0].as_s
    content.upstream_dir = "upstream"
    content.pkgbuild_source = upstream_info["pkgbuild_source"][0].as_s if upstream_info["pkgbuild_source"]?
    content.waited = {job.id => "job_health"}
    content.services = {
      "SCHED_HOST" => ENV["SCHED_HOST"],
      "SCHED_PORT" => ENV["SCHED_PORT"],
    }
    content.runtime = "36000"

    # add user specify build params
    params.each do |k, v|
      # if params key match config*, try link file to pkgbuild config dir
      if k =~ /config.*/
        field_name = k
        filename = File.basename(v)
        #get origin uploaded_file
        ss_upload_filepath = "#{SRV_USER_FILE_UPLOAD}/#{job.suite}/ss.#{pkg_name}.#{field_name}/#{filename}"
        if File.exists?(ss_upload_filepath)
          _pkgbuild_repo = content.pkgbuild_repo
          _pkg_name = _pkgbuild_repo.chomp.split('/', remove_empty: true)[-1]
          dest_dir = "#{SRV_USER_FILE_UPLOAD}/pkgbuild/#{pkg_name}/#{field_name}"
          pkg_dest_file = "#{dest_dir}/#{filename}"
          FileUtils.mkdir_p(dest_dir) unless File.exists?(dest_dir)
          #link file
          File.symlink(ss_upload_filepath, pkg_dest_file) unless File.exists?(pkg_dest_file)
        end
      end
      content.hash_any[k] = v
    end

    default = load_default_pkgbuild_yaml

    if content.commit == "HEAD"
      upstream_commit = get_head_commit(upstream_repo)
    else
      upstream_commit = content.commit
    end
    content.upstream_commit = upstream_commit

    content.import2hash(default)
    @log.info(content)
    return content
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

  def create_pkgbuild_yaml(id, pkg_name, content)
    job_yaml = "/tmp/yaml/#{id}_#{pkg_name}.yaml"
    dir_name = File.dirname(job_yaml)
    FileUtils.mkdir_p(dir_name) unless File.exists?(dir_name)
    File.open(job_yaml, "w") { |f| f.puts content.to_yaml }

    return job_yaml
  end

  def load_default_pkgbuild_yaml
    content = YAML.parse(File.open("#{ENV["LKP_SRC"]}/programs/pkgbuild/jobs/pkgbuild.yaml"))
    content = Hash(String, JSON::Any).from_json(content.to_json)

    return content
  end

  # add new desired value to sched/wait/$queue/$subqueue/$id
  def add_desired2queue(job, value)
    key = "sched/wait/#{job.queue}/#{job.subqueue}/#{job.id}"
    res = @etcd.range(key)
    raise "can't find the value of key in etcd, key: #{key}" if res.count == 0

    k_v = JSON.parse(res.kvs[0].value.not_nil!).as_h
    if k_v.has_key?("desired")
      d_v = k_v["desired"].as_h
      d_v.any_merge!(value)
      k_v.any_merge!({"desired" => d_v})
    else
      k_v.any_merge!({"desired" => value})
    end

    @etcd.update(key, k_v.to_json)
    job.wait = k_v["desired"]
  end

  # update waited field of id2job
  # waited_value = {job.id => "job_health"}
  def add_waited2job(waited_id, waited_value)
    key = "sched/id2job/#{waited_id}"
    # update waited of id2job in etcd
    return loop_update_waited(key, waited_value)
  end

  # waited_field = {job.id => "job_health"}
  def update_wait_current_from_es(wait_job, waited_id, waited_field)
    waited_job = @es.get_job(waited_id.not_nil!)
    raise "cant find the job in es, job id: #{waited_id}" unless waited_job

    finally_state = waited_job[waited_field]
    wait_key = "sched/wait/#{wait_job.queue}/#{wait_job.subqueue}/#{wait_job.id}"
    current = {waited_id => JSON.parse({waited_field => finally_state}.to_json)}
    loop_update_current(wait_key, current)
  end
end
