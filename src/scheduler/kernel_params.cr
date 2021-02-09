# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Job
  private def kernel_common_params
    common_params = "user=lkp job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job ip=dhcp"
    return "#{common_params} rw" if "#{self.os_mount}" == "local"
    return "#{common_params} rootovl ro"
  end

  private def kernel_custom_params
    return @hash["kernel_custom_params"] if @hash["kernel_custom_params"]?
  end

  def kernel_append_root
    os_real_path = JobHelper.service_path("#{SRV_OS}/#{os_dir}")

    fs2root = {
      "nfs"  => "root=#{OS_HTTP_HOST}:#{os_real_path}",
      "cifs" => "root=cifs://#{OS_HTTP_HOST}#{os_real_path}" +
                ",guest,ro,hard,vers=1.0,noacl,nouser_xattr",
      "initramfs" => "rdinit=/sbin/init prompt_ramdisk=0",
      "local" => "root=/dev/mapper/os-#{self.os}_#{self.os_arch}_#{self.os_version}",
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
    @hash["ipxe_kernel_params"] = JSON.parse(initrds_basename.to_json)
  end
end
