# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Job < JobHash
  private def kernel_common_params
    params = "user=lkp job=/lkp/scheduled/job.yaml ip=dhcp"
    return "#{params} rootovl ro" unless "#{self.os_mount}" == "local"

    os_info = "#{self.os}_#{self.os_arch}_#{self.os_version.gsub('-', '_')}"

    # two way to use local lvm:
    # - os_lv: job will always use one lv
    # - src_lv_suffix + boot_lv_suffix: job can specify the src_lv and boot_lv

    params += " local rw os_version=#{self.os_version}"
    params += " os_partition=/dev/mapper/os-#{os_info}_#{self.os_lv.gsub('-', '_')}" if @hash_plain["os_lv"]?

    params += " use_root_partition=/dev/mapper/os-#{os_info}_#{self.src_lv_suffix}" if @hash_plain["src_lv_suffix"]?
    params += " save_root_partition=/dev/mapper/os-#{os_info}_#{self.boot_lv_suffix}" if @hash_plain["boot_lv_suffix"]?
    @hash_plain["os_lv_size"] ||= "20G"
    params += " os_lv_size=#{self.os_lv_size}"
    params
  end

  private def kernel_custom_params
    @hash_plain["kernel_custom_params"]?
  end

  # job:
  #   boot_params:
  #   bp_trace_buf_size: 131072K
  #   bp_trace_clock: x86-tsc
  # output string:
  #   trace_buf_size=131072K trace_clock=x86-tsc
  private def job_boot_params
    return nil unless @hash_hh["boot_params"]?

    cmdline = ""
    @hash_hh["boot_params"].each do |k, v|
      if v
        cmdline += "#{k.sub(/^bp\d*_/, "")}=#{v} "
      else
        cmdline += "#{k} "
      end
    end
    cmdline.strip
  end

  def kernel_append_root
    os_real_path = JobHelper.service_path("#{SRV_OS}/#{os_dir}")

    fs2root = {
      "nfs"  => "root=#{OS_HTTP_HOST}:#{os_real_path}",
      "cifs" => "root=cifs://#{OS_HTTP_HOST}#{os_real_path}" +
                ",guest,ro,hard,vers=1.0,noacl,nouser_xattr,noserverino",
      "initramfs" => "rdinit=/sbin/init prompt_ramdisk=0",
      "local" => "root=#{OS_HTTP_HOST}:#{os_real_path}", # root is just used to temporarily mount a root in initqueue stage when lvm is not ready
      "container" => "",
    }

    fs2root[os_mount]
  end

  private def kernel_console
    return "console=tty0 console=ttyS0,115200" if os_arch == "x86_64"
  end

  private def set_kernel_params
    kernel_params_values = "#{kernel_common_params()} #{job_boot_params()} #{kernel_custom_params()} #{self.kernel_append_root} #{kernel_console()}"
    kernel_params_values = kernel_params_values.split(" ").map(&.strip()).reject!(&.empty?)
    @hash_array["kernel_params"] = kernel_params_values
  end
end
