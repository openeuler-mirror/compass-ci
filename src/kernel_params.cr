# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class JobHash
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

  # job:
  #   boot_params:
  #   bp_trace_buf_size: 131072K
  #   bp_trace_clock: x86-tsc
  # output string:
  #   trace_buf_size=131072K trace_clock=x86-tsc
  private def job_boot_params
    return nil unless bps = self.boot_params?

    cmdline = ""
    bps.each do |k, v|
      if v
        cmdline += "#{k.sub(/^bp\d*_/, "")}=#{v} "
      else
        cmdline += "#{k} "
      end
    end
    cmdline.strip
  end

  def os_real_path
    JobHelper.service_path("#{SRV_OS}/#{os_dir}")
  end

  def kernel_append_root
    case os_mount
    when "nfs"
      "root=#{OS_HTTP_HOST}:#{os_real_path}"
    when "cifs"
      "root=cifs://#{OS_HTTP_HOST}#{os_real_path},guest,ro,hard,vers=1.0,noacl,nouser_xattr,noserverino"
    when "initramfs"
      ""
    when "local"
      "root=#{OS_HTTP_HOST}:#{os_real_path}" # root is just used to temporarily mount a root in initqueue stage when lvm is not ready
    when "container"
      ""
    else
      raise "Unsupported mount type: #{os_mount}"
    end
  end

  private def kernel_console
    return "console=tty0 console=ttyS0,115200" if os_arch == "x86_64"
    return "console=tty0 console=ttyAMA0,115200" if os_arch == "aarch64"
  end

  private def set_kernel_params
    kernel_params_values = "#{kernel_common_params()} #{job_boot_params()} #{kernel_custom_params?} #{self.kernel_append_root} #{kernel_console()}"
    kernel_params_values = kernel_params_values.split(" ").map(&.strip()).reject!(&.empty?)
    self.kernel_params = kernel_params_values
  end

  def update_kernel_params
    host_info = Utils.get_host_info(self.testbox)
    return unless host_info

    hw_job = JobHash.new({"hw" => host_info})
    set_crashkernel(Utils.get_crashkernel(host_info.as_h)) unless self.crashkernel?
    self.merge!(hw_job)
  end

  def set_crashkernel(p)
    self.crashkernel = p
  end

  def boot_dir
    return "#{SRV_OS}/#{os_dir}/boot"
  end

  def boot2os_dir
    return "#{FILE_STORE}/boot2os/#{arch}/#{osv}"
  end

  def global_boot2os_dir
    return "#{GLOBAL_FILE_STORE}/boot2os/#{arch}/#{osv}"
  end

  def os_dir
    return "#{os}/#{os_arch}/#{os_version}"
  end

  # the OS default kernel
  private def set_os_kernel
    return if os_mount == "container"
    return if @hash_plain.has_key?("kernel_uri") # set by ss.linux

    set_os_kernel_version()
    set_os_kernel_uri()
  end

  private def set_os_kernel_version
    # kernel_version may be specified by user
    return if @hash_plain.has_key? "kernel_version"

    if File.exists? "#{boot2os_dir}/vmlinuz"
      vmlinuz_path = "#{boot2os_dir}/vmlinuz"
    elsif !IS_ROOT_USER && File.exists? "#{global_boot2os_dir}/vmlinuz"
      vmlinuz_path = "#{global_boot2os_dir}/vmlinuz"
    else
      vmlinuz_path = "#{boot_dir}/vmlinuz"
    end
    self.kernel_version = File.basename(File.realpath vmlinuz_path).gsub("vmlinuz-", "")
  end

  private def set_os_kernel_uri
    return if @hash_plain.has_key?("kernel_uri")

    if File.exists? "#{boot2os_dir}/vmlinuz-#{kernel_version}"
      vmlinuz_path = File.realpath("#{boot2os_dir}/vmlinuz-#{kernel_version}")
      modules_path = File.realpath("#{boot2os_dir}/modules-#{kernel_version}.cgz")
    elsif !IS_ROOT_USER && File.exists? "#{global_boot2os_dir}/vmlinuz-#{kernel_version}"
      vmlinuz_path = File.realpath("#{global_boot2os_dir}/vmlinuz-#{kernel_version}")
      modules_path = File.realpath("#{global_boot2os_dir}/modules-#{kernel_version}.cgz")
    else
      vmlinuz_path = File.realpath("#{boot_dir}/vmlinuz-#{kernel_version}")
      modules_path = File.realpath("#{boot_dir}/modules-#{kernel_version}.cgz")
    end
    self.kernel_uri = "#{os_http_prefix}" + JobHelper.service_path(vmlinuz_path)
    self.modules_uri = ["#{os_http_prefix}" + JobHelper.service_path(modules_path)] unless self.os_mount == "local"
  end

  # http://172.168.131.113:8800/kernel/aarch64/config-4.19.90-2003.4.0.0036.oe1.aarch64/v5.10/vmlinuz
  def update_kernel_uri(full_kernel_uri)
    self.kernel_uri = full_kernel_uri
  end

  # http://172.168.131.113:8800/kernel/aarch64/config-4.19.90-2003.4.0.0036.oe1.aarch64/v5.10/modules.cgz
  def update_modules_uri(full_modules_uri)
    self.modules_uri = full_modules_uri
  end

  def os_http_prefix
    @is_remote ? ENV["DOMAIN_NAME"] : OS_HTTP_PREFIX
  end

  def initrd_http_prefix
    @is_remote ? ENV["DOMAIN_NAME"] : INITRD_HTTP_PREFIX
  end

  def sched_http_prefix
    @is_remote ? ENV["DOMAIN_NAME"] : SCHED_HTTP_PREFIX
  end

  def get_common_initrds
    temp_initrds = [] of String

    # init custom_bootstrap cgz
    # if has custom_bootstrap field, just give bootstrap cgz to testbox, no need lkp-test/job cgz
    if @hash_plain.has_key?("custom_bootstrap")
      raise "need runtime field in the job yaml." unless @hash_plain.has_key?("runtime")

      temp_initrds << "#{initrd_http_prefix}" +
        JobHelper.service_path("#{SRV_INITRD}/custom_bootstrap/#{self.my_email}/bootstrap-#{os_arch}.cgz")

      return temp_initrds
    end

    if @hash_array.has_key? "need_file_store"
      @hash_array["need_file_store"].each do |path|
        case path
        when /\/vmlinuz$/
          self.kernel_uri = "#{sched_http_prefix}/srv/file-store/#{path}"
        when /\.cgz$/
          temp_initrds << "#{sched_http_prefix}/srv/file-store/#{path}"
        end
      end
    elsif @hash_hhh["pkg_data"]?
    # pkg_data:
    #   lkp-tests:
    #     tag: v1.0
    #     md5: xxxx
    #     content: yyy (base64)
    @hash_hhh["pkg_data"].each do |key, value|
      next unless value
      program = value
      temp_initrds << "#{initrd_http_prefix}" +
        JobHelper.service_path("#{SRV_UPLOAD}/#{key}/#{os_arch}/#{program["tag"]}.cgz")
      temp_initrds << "#{initrd_http_prefix}" +
        JobHelper.service_path("#{SRV_UPLOAD}/#{key}/#{program["md5"].to_s[0,2]}/#{program["md5"]}.cgz")
    end
    else
      puts "Error: empty pkg_data in job #{id}"
    end

    # append job.cgz in the end, when download finish, we'll auto mark job_stage="boot"
    temp_initrds << "#{sched_http_prefix}/srv/scheduler/pending-jobs/#{id}/job.cgz"

    return temp_initrds
  end

  private def initramfs_initrds
    temp_initrds = [] of String

    osimage_dir = "#{SRV_INITRD}/osimage/#{os_dir}"
    osimage = "#{SRV_INITRD}/osimage/#{os_dir}/current"
    if File.exists? osimage
      temp_initrds << "#{initrd_http_prefix}" + JobHelper.service_path(osimage)
    end

    osimage = "#{FILE_STORE}/docker2os/#{self.arch}/#{self.osv}.cgz"
    if File.exists? osimage
      temp_initrds << "#{initrd_http_prefix}" + JobHelper.service_path(osimage)
    elsif !IS_ROOT_USER
      osimage = "#{GLOBAL_FILE_STORE}/docker2os/#{self.arch}/#{self.osv}.cgz"
      if File.exists? osimage
        temp_initrds << "#{initrd_http_prefix}" + JobHelper.service_path(osimage)
      end
    end

    if File.exists? "#{FILE_STORE}/busybox/#{self.arch}/busybox-static.cgz"
      temp_initrds << "#{sched_http_prefix}/srv/file-store/busybox/#{self.arch}/busybox-static.cgz"
    elsif !IS_ROOT_USER && File.exists? "#{GLOBAL_FILE_STORE}/busybox/#{self.arch}/busybox-static.cgz"
      temp_initrds << "#{sched_http_prefix}/srv/file-store/busybox/#{self.arch}/busybox-static.cgz"
    elsif File.exists? "#{osimage_dir}/run-ipconfig.cgz"
      temp_initrds << "#{initrd_http_prefix}" +
                    JobHelper.service_path("#{osimage_dir}/run-ipconfig.cgz")
    end

    temp_initrds.concat(self.initrd_deps)
    temp_initrds.concat(self.initrd_pkgs)
    return temp_initrds
  end

  private def nfs_cifs_initrds
    temp_initrds = [] of String

    temp_initrds << "#{os_http_prefix}" +
                    JobHelper.service_path("#{SRV_OS}/#{os_dir}/initrd.lkp")

    return temp_initrds
  end

  private def get_initrds
    temp_initrds = [] of String

    if self.os_mount == "initramfs"
      temp_initrds.concat(initramfs_initrds())
    elsif ["nfs", "cifs", "local"].includes? self.os_mount
      temp_initrds.concat(nfs_cifs_initrds())
    end

    temp_initrds.concat(get_common_initrds())

    return temp_initrds
  end

  private def set_initrds_uri
    self.initrds_uri = get_initrds()
  end

  private def set_depends_initrd
    initrd_deps_arr = Array(String).new
    initrd_pkgs_arr = Array(String).new

    get_depends_initrd(get_program_params(), initrd_deps_arr, initrd_pkgs_arr)

    self.initrd_deps = initrd_deps_arr.uniq
    self.initrd_pkgs = initrd_pkgs_arr.uniq
  end

  private def get_program_params
    program_params = HashHH.new
    program_params.merge!(@hash_hhh["monitor"]) if @hash_hhh["monitor"]?
    program_params.merge!(@hash_hhh["monitors"]) if @hash_hhh["monitors"]? # to be removed in future
    program_params.merge!(@hash_hhh["pp"]) if @hash_hhh["pp"]?
    program_params
  end

  private def get_depends_initrd(program_params, initrd_deps_arr, initrd_pkgs_arr)
    mount_type = self.os_mount == "cifs" ? "nfs" : self.os_mount

    # init deps lkp.cgz
    deps_lkp_cgz = "#{SRV_INITRD}/deps/#{mount_type}/#{self.os_dir}/lkp/lkp.cgz"
    if File.exists?(deps_lkp_cgz)
      initrd_deps_arr << "#{initrd_http_prefix}" + JobHelper.service_path(deps_lkp_cgz)
    end

    program_params.keys.each do |program|
      if program =~ /^(.*)-\d+$/
        program = $1
      end

      # XXX
      if @hash_any["#{program}_version"]?
        program_version = @hash_any["#{program}_version"].as_s
      else
        program_version = "latest"
      end

      deps_dest_file = "#{SRV_INITRD}/deps/#{mount_type}/#{self.os_dir}/#{program}/#{program}.cgz"
      pkg_dest_file = "#{SRV_INITRD}/pkg/#{mount_type}/#{self.os_dir}/#{program}/#{program_version}.cgz"

      if File.exists?(deps_dest_file)
        initrd_deps_arr << "#{initrd_http_prefix}" + JobHelper.service_path(deps_dest_file)
      end
      if File.exists?(pkg_dest_file)
        initrd_pkgs_arr << "#{initrd_http_prefix}" + JobHelper.service_path(pkg_dest_file)
      end
    end
  end

end
