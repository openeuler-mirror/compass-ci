# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
#
require "./get_job"

require "../lib/common"
require "../lib/json_logger"
require "../lib/string_utils"

class Sched
  def find_job_boot
    job = nil
    @env.set "job_stage", "boot"

    if @env.get?("ws")
      @log.info("get job boot content")

      send_timeout_signal

      hostname = @env.params.query["hostname"]
      is_remote = @env.params.query["is_remote"]
      boot_type = @env.ws_route_lookup.params["boot_type"]
    else
      hostname = @env.params.url["hostname"]
      is_remote = @env.params.url["is_remote"]
      boot_type = @env.params.url["boot_type"]
    end

    host = is_remote == "true" ? "remote-#{hostname}" : "local-#{hostname}"

    @env.set "testbox", host

    # get job
    response, job = create_job_boot(host, boot_type)

    # set job_id to @env
    job_id = response[/tmpfs\/(.*)\/job\.cgz/, 1]?
    @env.set "job_id", job_id

    set_job2watch(job, "boot", "success")

    # return response to testbox
    if @env.get?("ws")
      @env.socket.send({
        "type" => "boot",
        "response" => response
      }.to_json) unless @env.get?("ws_state") == "close"
    else
      response
    end
  rescue e
    set_job2watch(job, "boot", "failed")
    @env.response.status_code = 500
    @log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  ensure
    close_resources
    send_mq_msg
  end

  def close_resources
    return unless @env.get?("ws")

    begin
      @env.socket.send({"type" => "close"}.to_json)
    rescue e
      @log.warn({
        "message" => "socket send close message failed",
        "error_message" => e.to_s
      }.to_json)
    end

    begin
      @env.socket.close
    rescue e
      @log.warn({
        "message" => "close socket failed",
        "error_message" => e.to_s
      }.to_json)
    end

    begin
      @env.channel.close
    rescue e
      @log.warn({
        "message" => "close channel failed",
        "error_message" => e.to_s
      }.to_json)
    end
  end

  def send_timeout_signal
    spawn do
      90.times do
        sleep 2
        break if @env.channel.closed?
      end

      @env.channel.send({"type" => "timeout"}) unless @env.channel.closed?
    end
  end

  def get_job_from_ready_queues(boot_type, testbox)
    job = nil
    host_machine = testbox.split_keep_left('-')
    return job if testbox.nil?

    case boot_type
    when "container"
      @log.info("container get job from ready queues by host_machine: #{host_machine}")
      etcd_job = GetJob.new.get_job_by_tbox_type(host_machine, "dc")
    when "ipxe"
      @log.info("qemu get job from ready queues by host_machine: #{host_machine}")
      etcd_job = GetJob.new.get_job_by_tbox_type(host_machine, "vm")
    end

    return nil unless etcd_job

    @log.info("get job from ready queues, etcd_job: #{etcd_job}, host_machine: #{host_machine}")

    job_id = etcd_job["id"]
    if job_id
      begin
        job = @es.get_job(job_id.to_s)
        @log.warn("job_is_nil, job id=#{job_id.to_s}") unless job
      rescue ex
        @log.warn("Invalid job (id=#{job_id}) in es. Info: #{ex}")
        @log.warn(ex.inspect_with_backtrace)
      end
    end

    if job
      @log.info("#{testbox} got the job #{job_id}")
      if testbox.starts_with?("remote-")
        job.set_remote_testbox_env()
        job.set_http_prefix()
      end

      job.set_remote_mount_repo()
      job.update({"testbox" => testbox, "host_machine" => host_machine})
      job.update_kernel_params
      job.set_result_root
      job.set_time("boot_time")
      @log.info(%({"job_id": "#{job_id}",
                "result_root": "/srv#{job.result_root}",
                "job_state": "set result root"}))
      update_id2job(job)
    end

    return job
  end

  def set_job2watch(job, stage, health)
    return unless job

    if !job["in_watch_queue"].empty?
      current_time = Time.local.to_s("%Y-%m-%d %H:%M:%S")
      data = {"job_id" => job["id"], "job_stage" => stage, "job_health" => health, "current_time" => current_time}
      @etcd.put_not_exists("watch_queue/#{job["in_watch_queue"]}/#{job["id"]}", data.to_json)
    end
  end

  def create_job_boot(host, boot_type)
    @env.set "state", "requesting"
    send_mq_msg

    job = get_job_from_ready_queues(boot_type, host)
    update_testbox_and_job(job, host, ["//#{host}"]) if job

    if job
      job.last_success_stage = "boot"
      @env.set "job_id", job.id
      @env.set "deadline", job.deadline
      @env.set "job_stage", job.job_stage
      @env.set "state", "booting"
      create_job_cpio(job, Kemal.config.public_folder)

       # UPDATE the large fields to null
       job.job2sh = JSON::Any.new(nil)
       job.services = nil
       @es.set_job(job)
       report_workflow_job_event(job.id, job)
    end

    return boot_content(job, boot_type), job
  end

  private def boot_msg(boot_type, msg)
    "#!#{boot_type}
        echo ...
        echo #{msg}
        echo ...
        chain http://#{ENV["SCHED_HOST"]}:#{ENV["SCHED_PORT"]}/boot.ipxe/mac/${mac:hexhyp}"
  end

  private def get_boot_container(job : Job)
    response = Hash(String, String).new
    response["job_id"] = job.id.to_s
    response["docker_image"] = "#{job.docker_image}"
    response["initrds"] = job.get_common_initrds().to_json
    response["memory_minimum"] = "#{job["memory_minimum"]}"
    if cpu = job.hw.not_nil!.["nr_cpu"]?
      response["nr_cpu"] = cpu
    end

    if mem = job.hw.not_nil!.["memory"]?
      response["memory"] = mem 
    end

    return response.to_json
  end

  private def get_boot_native(job : Job)
    response = Hash(String, String).new
    response["job_id"] = job.id.to_s
    response["initrds"] = job.get_common_initrds().to_json

    return response.to_json
  end

  private def get_boot_grub(job : Job)
    initrd_lkp_cgz = "lkp-#{job.os_arch}.cgz"

    response = "#!grub\n\n"
    response += "linux (http,#{OS_HTTP_HOST}:#{OS_HTTP_PORT})"
    response += "#{JobHelper.service_path("#{SRV_OS}/#{job.os_dir}/vmlinuz")} user=lkp"
    response += " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job"
    response += " rootovl ip=dhcp ro root=#{job.kernel_append_root}\n"

    response += "initrd (http,#{OS_HTTP_HOST}:#{OS_HTTP_PORT})"
    response += JobHelper.service_path("#{SRV_OS}/#{job.os_dir}/initrd.lkp")
    response += " (http,#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT})"
    response += JobHelper.service_path("#{SRV_INITRD}/lkp/#{job.lkp_initrd_user || "latest"}/#{initrd_lkp_cgz}")
    response += " (http,#{SCHED_HOST}:#{SCHED_PORT})/job_initrd_tmpfs/"
    response += "#{job.id}/job.cgz\n"

    response += "boot\n"

    return response
  end

  private def get_vmlinuz_uri(cpio_dir, initrd_dir)
    vmlinuz_uri = ""
    boot_dir = File.join(cpio_dir, "boot")
    if Dir.exists?(boot_dir)
      Dir.each_child(File.join(cpio_dir, "boot")) do |entry|
        if entry.starts_with?("vmlinuz-")
          File.copy("#{cpio_dir}/boot/#{entry}", "#{initrd_dir}/#{entry}")
          vmlinuz_uri = "#{INITRD_HTTP_PREFIX}/#{initrd_dir.sub("/srv/", "")}/#{entry}"
          break
        end
      end
    end

    return vmlinuz_uri
  end

  private def get_modules_uri(cpio_dir, initrd_dir)
    modules_uri = ""
    modules_dir = File.join(cpio_dir, "lib", "modules")
    output_file = "modules.cgz"
    if Dir.exists?(modules_dir)
      result = Process.run("sh", args: ["-c", "cd #{cpio_dir} && for tt in $(find ./ -type f -name *.xz); do unxz -q $tt ;done"])
      raise "unzx #{cpio_dir} error" if result.exit_code != 0

      result = Process.run("sh", args: ["-c", "cd #{cpio_dir} && find lib/modules |cpio --quiet -o -H newc | gzip -q > #{output_file}"])
      raise "cpio #{cpio_dir} error" if result.exit_code != 0

      FileUtils.mkdir_p(initrd_dir)
      File.copy("#{cpio_dir}/#{output_file}", "#{initrd_dir}/#{output_file}")
      modules_uri = "#{INITRD_HTTP_PREFIX}/#{initrd_dir.sub("/srv/", "")}/#{output_file}"
    end

    return modules_uri
  end

  private def init_3rd_party_kernel(job : Job)
    return "", ""  unless job.kernel_rpms_url?
    job_id = job.id

    kernel_cache_dir = "/srv/initrd/osimage/custom/kernel_cache_dir"
    rpms_dir = "#{kernel_cache_dir}/rpms"
    cpio_dir = "#{kernel_cache_dir}/cpio/#{job_id}"
    initrd_dir = "#{kernel_cache_dir}/initrds/#{job_id}"

    FileUtils.mkdir_p(rpms_dir)
    FileUtils.mkdir_p(cpio_dir)
    FileUtils.mkdir_p(initrd_dir)

    rpms = [] of String
    job.kernel_rpms_url.each do |rpm_url|
      rpm = rpm_url.split("/").last
      rpms << rpm
      exit_code = Common.download_file(rpm_url, "#{rpms_dir}/#{rpm}", rpms_dir)
      raise "downlaod #{rpm_url} to #{rpms_dir} error, exit_code: #{exit_code}" if exit_code != 0
    end

    rpms.each do |rpm|
      result = Process.run("sh", args: ["-c", "rpm2cpio #{rpms_dir}/#{rpm} | cpio -idmv -D  #{cpio_dir}"])
      raise "rpm2cpio #{rpms_dir}/#{rpm} to #{cpio_dir} error." if result.exit_code != 0
    end

    vmlinuz_uri = get_vmlinuz_uri(cpio_dir, initrd_dir)
    modules_uri = get_modules_uri(cpio_dir, initrd_dir)

    return vmlinuz_uri, modules_uri
  end

  private def get_boot_ipxe(job : Job)
    return job.custom_ipxe if job.suite.starts_with?("install-iso") && job.has_key?("custom_ipxe")

    response = "#!ipxe\n\n"
    response += "# nr_nic=" + job.nr_nic + "\n" if job.has_key?("nr_nic")

    _3rd_vmlinuz_uri, _3rd_modules_uri = init_3rd_party_kernel(job)
    _initrds_uri = job.initrds_uri.map { |uri| "initrd #{uri}" }

    if !_3rd_modules_uri.empty?
      _initrds_uri.insert(1, "initrd #{_3rd_modules_uri}")
    elsif job.modules_uri?
      job.modules_uri.reverse_each do |ele|
        _initrds_uri.insert(1, "initrd #{ele}")
      end
    end

    _kernel_initrds = _initrds_uri.map { |initrd| " initrd=#{File.basename(initrd.split("initrd ")[-1])}"}
    response += _initrds_uri.join("\n") + "\n"

    _vmlinuz_uri = job.kernel_uri
    if !_3rd_vmlinuz_uri.empty?
      _vmlinuz_uri =  _3rd_vmlinuz_uri
    end
    _kernel_params = ["kernel #{_vmlinuz_uri}"] + job.kernel_params + _kernel_initrds
    response += _kernel_params.join(" ")
    response += " rootfs_disk=#{job.hw.not_nil!["rootfs_disk"].gsub("\n", ".")}" if job.hw.not_nil!.has_key? "rootfs_disk"
    response += " crashkernel=#{job.crashkernel}" if job.crashkernel? && !response.includes?("crashkernel=")
    response += "\necho ipxe will boot job id=#{job.id}, ip=${ip}, mac=${mac}" # the ip/mac will be expanded by ipxe

    response += "\necho result_root=#{job.result_root}\n"
    response += "\nboot\n"

    return response
  end

  private def get_boot_libvirt(job : Job)
    _kernel_params = job.kernel_params?
    _kernel_params = _kernel_params.map(&.to_s).join(" ") if _kernel_params

    _vt = job.vt? || Hash(String, String).new

    return {
      "job_id"             => job.id,
      "kernel_uri"         => job.kernel_uri,
      "initrds_uri"        => job.initrds_uri?,
      "kernel_params"      => _kernel_params,
      "result_root"        => job.result_root,
      "LKP_SERVER"         => job.services.not_nil!["LKP_SERVER"],
      "vt"                 => _vt,
      "RESULT_WEBDAV_PORT" => job.services.not_nil!["RESULT_WEBDAV_PORT"]? || "3080",
      "SRV_HTTP_CCI_HOST"  => SRV_HTTP_CCI_HOST,
      "SRV_HTTP_CCI_PORT"  => SRV_HTTP_CCI_PORT,
    }.to_json
  end

  def set_id2upload_dirs(job)
    @log.info("set sched/id2upload_dirs #{job.id}, #{job.upload_dirs}")
    @redis.hash_set("sched/id2upload_dirs", job.id, job.upload_dirs)
  end

  def boot_content(job : Job | Nil, boot_type : String)
    set_id2upload_dirs(job) if job

    case boot_type
    when "ipxe"
      return job ? get_boot_ipxe(job) : boot_msg(boot_type, "No job now")
    when "grub"
      return job ? get_boot_grub(job) : boot_msg(boot_type, "No job now")
    when "native"
      return job ? get_boot_native(job) : {"job_id" => "0"}.to_json
    when "container"
      return job ? get_boot_container(job) : {"job_id" => "0"}.to_json
    when "libvirt"
      return job ? get_boot_libvirt(job) : {"job_id" => ""}.to_json
    else
      raise "Not defined boot type #{boot_type}"
    end
  end
end
