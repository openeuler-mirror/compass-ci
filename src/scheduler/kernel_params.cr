# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Job
  private def kernel_common_params
    common_params = "user=lkp job=/lkp/scheduled/job.yaml ip=dhcp"
    return "#{common_params} rootovl ro" unless "#{self.os_mount}" == "local"

    os_info = "#{os}_#{os_arch}_#{os_version.gsub('-', '_')}"

    # two way to use local lvm:
    # - os_lv: job will always use one lv
    # - src_lv_suffix + boot_lv_suffix: job can specify the src_lv and boot_lv
    os_partition = "/dev/mapper/os-#{os_info}_#{os_lv.gsub('-', '_')}" if @hash["os_lv"]? != nil

    use_root_partition = "/dev/mapper/os-#{os_info}_#{src_lv_suffix}" if @hash["src_lv_suffix"]? != nil
    save_root_partition = "/dev/mapper/os-#{os_info}_#{boot_lv_suffix}" if @hash["boot_lv_suffix"]? != nil
    os_lv_size = @hash["os_lv_size"]? != nil ? @hash["os_lv_size"] : "10G"
    return "#{common_params} local use_root_partition=#{use_root_partition} save_root_partition=#{save_root_partition} os_version=#{os_version} os_lv_size=#{os_lv_size} os_partition=#{os_partition} rw"
  end

  private def kernel_custom_params
    return @hash["kernel_custom_params"] if @hash["kernel_custom_params"]?
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
    return "console=ttyS0,115200 console=tty0" if os_arch == "x86_64"
  end

  private def set_kernel_params
    kernel_params_values = "#{kernel_common_params()} #{kernel_custom_params()} #{self.kernel_append_root} #{kernel_console()}"
    kernel_params_values = kernel_params_values.split(" ").map(&.strip()).reject!(&.empty?)
    @hash["kernel_params"] = JSON.parse(kernel_params_values.to_json)
  end
end
