# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "file_utils"
require "json"
require "yaml"

module Jobfile::Operate
  def self.unzip_cgz(source_path : String, target_path : String)
    FileUtils.mkdir_p(target_path)
    cmd = "cd #{target_path};gzip -dc #{source_path}|cpio -id"
    system cmd
  end

  def self.prepare_lkp_tests(lkp_initrd_user = "latest", os_arch = "aarch64")
    expand_dir_base = File.expand_path(Kemal.config.public_folder +
                                       "/expand_cgz")
    FileUtils.mkdir_p(expand_dir_base)

    # update lkp-xxx.cgz if they are different
    target_path = update_lkp_when_different(expand_dir_base,
                                            lkp_initrd_user,
                                            os_arch)

    # delete oldest lkp, if exists too much
    del_lkp_if_too_much(expand_dir_base)

    return "#{target_path}/lkp/lkp/src"
  end

  # list *.cgz (lkp initrd), sorted in reverse time order
  # and delete 10 oldest cgz file, when exists more than 100
  # also delete the DIR expand from the cgz file
  def self.del_lkp_if_too_much(base_dir)
    file_list = `ls #{base_dir}/*.cgz -tr`
    file_array = file_list.split("\n")
    if file_array.size > 100
      10.times do |index|
        FileUtils.rm_rf(file_array[index])
        FileUtils.rm_rf(file_array[index].chomp(".cgz"))
      end
    end
  end

  def self.update_lkp_when_different(base_dir, lkp_initrd_user, os_arch)
    target_path = base_dir + "/#{lkp_initrd_user}-#{os_arch}"
    bak_lkp_filename = target_path + ".cgz"
    source_path = "#{SRV_INITRD}/lkp/#{lkp_initrd_user}/lkp-#{os_arch}.cgz"

    if File.exists?(bak_lkp_filename)
      # no need update
      return target_path if FileUtils.cmp(source_path, bak_lkp_filename)

      # remove last expanded lkp initrd DIR
      FileUtils.rm_rf(target_path)
    end

    # bakup user lkp-xxx.cgz (for next time check)
    FileUtils.cp(source_path, bak_lkp_filename)
    unzip_cgz(bak_lkp_filename, target_path)
    return target_path
  end

  # *fields* should be: ["field01=value01", "field02=value02", ...]
  def self.auto_submit_job(job_file, fields : Array(String) = ["testbox=vm-2p8g"])
    cmd = "#{ENV["LKP_SRC"]}/sbin/submit "
    cmd += "#{job_file} "
    cmd += fields.join(" ")
    puts `#{cmd}`
  end

  def self.auto_submit_job(job_file, fields : Hash(String, JSON::Any | String))
    array = Array(String).new
    fields.each do |k, v|
      array << "#{k}=#{v}"
    end

    cmd = "#{ENV["LKP_SRC"]}/sbin/submit "
    cmd += "#{job_file} "
    cmd += array.join(" ")
    puts `#{cmd}`
  end
end
