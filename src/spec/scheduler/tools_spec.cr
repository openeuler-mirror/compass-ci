# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "spec"
require "scheduler/tools"
require "file_utils"

describe Public do
  describe "hash replace" do
    it "can replace k:v" do
      hash_old = { "name" => "OldValue" }
      hash_new = { "name" => "NewValue" }
      hash_result = Public.hash_replace_with(hash_old, hash_new)

      (hash_result["name"]).should eq("NewValue")
    end

    it "can add k:v" do
      hash_old = { "name2" => "OldValue" }
      hash_new = { "name" => "NewValue" }
      hash_result = Public.hash_replace_with(hash_old, hash_new)

      (hash_result["name"]).should eq("NewValue")
      (hash_result["name2"]).should eq("OldValue")
    end
  end

  describe "get testgroup name from testbox name" do
    it "not end with -[n]" do
      testbox_name = "wfg-e595"
      testgroup_name = "wfg-e595"
      result = Public.get_tbox_group_name(testbox_name)

      result.should eq testgroup_name
    end

    it "no -" do
      testbox_name = "test_"
      testgroup_name = "test_"
      result = Public.get_tbox_group_name(testbox_name)

      result.should eq testgroup_name
    end

    it "end with -" do
      testbox_name = "myhost-"
      testgroup_name = "myhost-"
      result = Public.get_tbox_group_name(testbox_name)

      result.should eq testgroup_name
    end

    it "end with 1 -[n]" do
      testbox_name = "hostname-002"
      testgroup_name = "hostname"
      result = Public.get_tbox_group_name(testbox_name)

      result.should eq testgroup_name
    end

    it "instance: vm-pxe-hi1620-1p1g-chief-1338976" do
      testbox = "vm-pxe-hi1620-1p1g-chief-1338976"
      tbox_group = "vm-pxe-hi1620-1p1g-chief"
      result = Public.get_tbox_group_name(testbox)

      result.should eq tbox_group
    end

    it "end with 2 -[n]" do
      testbox_name = "hostname-001-001"
      testgroup_name = "hostname-001"
      result = Public.get_tbox_group_name(testbox_name)

      result.should eq testgroup_name
    end
  end

  describe "unzip cgz" do
    it "can unzip the cgz completely in the target_path" do
      test_file_tree = "/c/cci/scheduler/test_dir/test_dir/"
      FileUtils.mkdir_p(test_file_tree)

      content = "Only if the content of the unzipped file have this content.\nSpec will passed"
      File.write("#{test_file_tree}check_file.check", content)

      source_path = "/c/cci/scheduler/test.cgz"
      target_path = "/c/cci/scheduler/expand_cgz/1024/"
      zip_cmd = "find test_dir | cpio --quiet -o -H newc | gzip > #{source_path}"
      system zip_cmd

      FileUtils.rm_rf("/c/cci/scheduler/test_dir")

      Public.unzip_cgz(source_path, target_path)

      if File.exists?("#{target_path}test_dir/test_dir/check_file.check")
        read_content = File.read("#{target_path}test_dir/test_dir/check_file.check")
      else
        content = "something was wrong"
        read_content = "null"
      end

      read_content.should eq content

      FileUtils.rm_rf("/c/cci/scheduler/expand_cgz")
      FileUtils.rm("/c/cci/scheduler/test.cgz")
    end
  end
end
