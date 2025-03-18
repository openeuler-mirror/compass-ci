# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
#

require "./common"
require "./lib/json_logger"
require "./lib/string_utils"

class Sched

  def on_job_dispatch(job : JobHash, hostreq : HostRequest)
    job.set_tbox_info(hostreq)
    job.settle_job_fields
    change_job_stage(job, "dispatch", nil)
    save_job_files(job, Kemal.config.public_folder)
    @hosts_cache.update_job_info(job)

    move_job_cache(job)

    @es.replace_doc("jobs", job)

    # Log/notify
    @log.info({"message" => "#{hostreq.hostname} got the job #{job.id}",
               "job_id" => "#{job.id}",
               "result_root" => "#{BASE_DIR}#{job.result_root}",
               "job_state" => "set result root"})
    # puts caller.join('\n')
    report_workflow_job_event(job["id"].to_s, job)
  end

  private def hw_boot_msg(boot_type, msg)
    "#!#{boot_type}
        echo ...
        echo #{msg}
        echo ...
        chain http://#{ENV["SCHED_HOST"]}:#{ENV["SCHED_PORT"]}/boot.ipxe/mac/${mac:hexhyp}?arch=${buildarch}&hostname=${hostname}&ip=${net0/ip}"
  end

  private def get_boot_container(job : JobHash)
    response = Hash(String, String).new
    response["type"] = "boot-job"
    response["job_id"] = job.id.to_s
    response["tbox_type"] = "dc"
    response["tbox_group"] = job.tbox_group
    response["docker_image"] = "#{job.docker_image}"
    response["initrds"] = job.get_common_initrds().to_json
    response["os"] = "#{job["os"]}"
    response["osv"] = "#{job["osv"]}"
    response["result_root"] = "#{job["result_root"]}"
    response["job_token"] = "#{job["job_token"]}"
    response["cache_dirs"] = job.cache_dirs.join(" ") if job.hash_array.has_key? "cache_dirs"
    response["build_mini_docker"] = job.hash_any["build_mini_docker"].as_s if job.hash_any.has_key? "build_mini_docker"
    response["cpu_minimum"] = job.hash_any["cpu_minimum"].as_i.to_s if job.hash_any.has_key? "cpu_minimum"
    response["memory_minimum"] = job["memory_minimum"] if job.has_key? "memory_minimum"
    response["ccache_enable"] = job.hash_any["ccache_enable"].as_s if job.hash_any.has_key? "ccache_enable"
    response["bin_shareable"] = job.hash_any["bin_shareable"].as_s if job.hash_any.has_key? "bin_shareable"
    if cpu = job.hw.not_nil!.["nr_cpu"]?
      response["nr_cpu"] = cpu
    end

    if mem = job.hw.not_nil!.["memory"]?
      response["memory"] = mem 
    end

    return response
  end

  private def get_boot_native(job : JobHash)
    response = Hash(String, String).new
    response["job_id"] = job.id.to_s
    response["initrds"] = job.get_common_initrds().to_json

    return response.to_json
  end

  private def get_boot_grub(job : JobHash)
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
    response += " (http,#{SCHED_HOST}:#{SCHED_PORT})/srv/scheduler/pending-jobs/"
    response += "#{job.id}/job.cgz\n"

    response += "boot\n"

    return response
  end

  private def get_vmlinuz_uri(job, cpio_dir, initrd_dir)
    vmlinuz_uri = ""
    boot_dir = File.join(cpio_dir, "boot")
    if Dir.exists?(boot_dir)
      Dir.each_child(File.join(cpio_dir, "boot")) do |entry|
        if entry.starts_with?("vmlinuz-")
          File.copy("#{cpio_dir}/boot/#{entry}", "#{initrd_dir}/#{entry}")
          vmlinuz_uri = "#{job.initrd_http_prefix}/#{initrd_dir.sub(BASE_DIR, "srv")}/#{entry}"
          break
        end
      end
    end

    return vmlinuz_uri
  end

  private def get_modules_uri(job, cpio_dir, initrd_dir)
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
      modules_uri = "#{job.initrd_http_prefix}/#{initrd_dir.sub(BASE_DIR, "srv")}/#{output_file}"
    end

    return modules_uri
  end

  private def init_3rd_party_kernel(job : JobHash)
    return "", ""  unless job.kernel_rpms_url?
    job_id = job.id

    kernel_cache_dir = "#{BASE_DIR}/initrd/osimage/custom/kernel_cache_dir"
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

    vmlinuz_uri = get_vmlinuz_uri(job, cpio_dir, initrd_dir)
    modules_uri = get_modules_uri(job, cpio_dir, initrd_dir)

    return vmlinuz_uri, modules_uri
  end

  private def get_boot_ipxe(job : JobHash)
    return job.custom_ipxe if job.suite.starts_with?("install-iso") && job.has_key?("custom_ipxe")

    response = "#!ipxe\n\n"
    response += "# nr_nic=" + job.nr_nic + "\n" if job.has_key?("nr_nic")
    response += "# nr_disk=" + job.nr_disk + "\n" if job.has_key?("nr_disk")
    response += "# disk_size=" + job.disk_size + "\n" if job.has_key?("disk_size")

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

  private def get_boot_libvirt(job : JobHash)
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

  # Only called from HW machine boot
  def boot_content(job : JobHash | Nil, boot_type : String)
    case boot_type
    when "ipxe"
      return job ? get_boot_ipxe(job) : hw_boot_msg(boot_type, "No job now")
    when "grub"
      return job ? get_boot_grub(job) : hw_boot_msg(boot_type, "No job now")
    when "native"
      return job ? get_boot_native(job) : {"job_id" => "0"}.to_json
    when "libvirt"
      return job ? get_boot_libvirt(job) : {"job_id" => ""}.to_json
    else
      raise "Not defined boot type #{boot_type}"
    end
  end
end
