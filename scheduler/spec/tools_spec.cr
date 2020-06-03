require "spec"
require "../src/tools"

describe Public do
    describe "hash replace" do
        it "can replace k:v" do
            hash_old = { "name" => "OldValue" }
            hash_new = { "name" => "NewValue" }
            hash_result = Public.hashReplaceWith(hash_old, hash_new)

            (hash_result["name"]).should eq("NewValue")
        end

        it "can add k:v" do
            hash_old = { "name2" => "OldValue" }
            hash_new = { "name" => "NewValue" }
            hash_result = Public.hashReplaceWith(hash_old, hash_new)

            (hash_result["name"]).should eq("NewValue")
            (hash_result["name2"]).should eq("OldValue")
        end
    end

    describe "get testgroup name from testbox name" do
        it "not end with -[n]" do
            testbox_name = "wfg-e595"
            testgroup_name = "wfg-e595"
            result = Public.getTestgroupName(testbox_name)

            (result).should eq testgroup_name
        end

        it "no -" do
            testbox_name = "test_"
            testgroup_name = "test_"
            result = Public.getTestgroupName(testbox_name)

            (result).should eq testgroup_name
        end

        it "end with -" do
            testbox_name = "myhost-"
            testgroup_name = "myhost-"
            result = Public.getTestgroupName(testbox_name)

            (result).should eq testgroup_name
        end

        it "end with 1 -[n]" do
            testbox_name = "hostname-002"
            testgroup_name = "hostname"
            result = Public.getTestgroupName(testbox_name)

            (result).should eq testgroup_name
        end

        it "instance: vm-pxe-hi1620-1p1g-chief-1338976" do
            testbox = "vm-pxe-hi1620-1p1g-chief-1338976"
            tbox_group = "vm-pxe-hi1620-1p1g-chief"
            result = Public.getTestgroupName(testbox)

            (result).should eq tbox_group
        end

        it "end with 2 -[n]" do
            testbox_name = "hostname-001-001"
            testgroup_name = "hostname-001"
            result = Public.getTestgroupName(testbox_name)

            (result).should eq testgroup_name
        end
    end
end
