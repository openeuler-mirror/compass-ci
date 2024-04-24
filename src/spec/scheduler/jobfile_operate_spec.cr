# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "spec"
require "scheduler/constants"
require "scheduler/jobfile_operate"

describe Jobfile::Operate do
  describe "update" do
    file_path = "test/update.yaml"
    section = "#! job"
    kv = {"id" => "123456"}

    Jobfile::Operate.prepare_dir(file_path)
    if File.exists?(file_path)
      FileUtils.rm(file_path)
    end

    it "When no find, then append at end" do
      File.open(file_path, "w") do |f|
        f.close
      end

      Jobfile::Operate.update(file_path, section, kv)

      linepre = ""
      File.each_line(file_path) do |line|
        linepre = line
      end
      linepre.should eq("#{kv.first_key}: #{kv[kv.first_key]}")
      FileUtils.rm(file_path)
    end

    it "When find, then replace it" do
      File.open(file_path, "w") do |f|
        f.puts("id: 000000")
      end
      Jobfile::Operate.update(file_path, section, kv)

      linepre = ""
      File.each_line(file_path) do |line|
        match_info = line.match(/id: (.*)/)
        if match_info
          linepre = "id: #{match_info.[1]}"
        end
      end

      linepre.should eq("#{kv.first_key}: #{kv[kv.first_key]}")
      FileUtils.rm(file_path)
    end

    it "When no find, but find section, then append in the section" do
      File.open(file_path, "w") do |f|
        f.puts("#! job/")
        f.puts("#! other")
      end
      Jobfile::Operate.update(file_path, section, kv)

      line_index = 0
      File.each_line(file_path) do |line|
        match_info = line.match(/id: (.*)/)
        line_index = line_index + 1
        if match_info
          break
        end
      end

      line_index.should eq(2)
      FileUtils.rm(file_path)
    end

    # is this the real specification?
    it "When find key & section, but they are not matched, ignore now" do
      File.open(file_path, "w") do |f|
        f.puts("#! job")
        f.puts("#! other")
        f.puts("id: 000000")
      end
      Jobfile::Operate.update(file_path, section, kv)

      line_index = 0
      File.each_line(file_path) do |line|
        match_info = line.match(/id: (.*)/)
        line_index = line_index + 1
        if match_info
          break
        end
      end

      line_index.should eq(3)
      FileUtils.rm(file_path)
    end
  end

  describe "create_job_cpio" do
    # when debug this,it seems to execute "chmod +x /c/lkp-tests/sbin/create-job-cpio.sh" to get permission
    it "from jobid create job.cgz" do
      job_id = "100"
      fs_root = "#{File.realpath(".")}/public"

      old_dir = ::File.join [fs_root, job_id]
      FileUtils.rm_r(old_dir) if File.exists?(old_dir)

      job_hash = JSON.parse(DEMO_JOB).as_h
      job_hash = job_hash.merge({"result_root" => fs_root, "id" => job_id})
      job_content = JSON.parse(job_hash.to_json)

      Jobfile::Operate.create_job_cpio(job_content, fs_root)
      (File.exists?(::File.join [old_dir, "job.cgz"])).should be_true
      FileUtils.rm_r(old_dir) if File.exists?(old_dir)
    end
  end
end
