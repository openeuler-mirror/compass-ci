require "spec"
require "lib/subqueue"
require "scheduler/elasticsearch_client.cr"


es = Elasticsearch::Client.new
es.create_subqueue({"subqueue" => "test-ut-1", "priority" => 9, "weight" => 20}, "test-ut-1")
es.create_subqueue({"subqueue" => "test-ut-2", "priority" => 1, "weight" => 100}, "test-ut-2")
sleep(1)

subqueue = Subqueue.new

describe Subqueue do
  it "get_weight" do
    subqueue.get_weight("test-ut-1").should eq 20
    subqueue.get_weight("test-ut-2").should eq 100
    subqueue.get_weight("test-ut-3").should eq 1
  end

  it "get_priority2subqueue" do
    subqueue.get_priority2subqueue(1).should eq ["test-ut-2"].to_set
    subqueue.get_priority2subqueue(9).should eq ["test-ut-1"].to_set
    subqueue.get_priority2subqueue(5).empty?.should be_true
  end

  it "get_subqueue_info" do
    info = subqueue.get_subqueue_info("test-ut-1")
    info["priority"].should eq 9
    info["weight"].should eq 20
  end
end
