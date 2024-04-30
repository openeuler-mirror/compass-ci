require "spec"
require "lib/queue"
require "lib/etcd_client"


etcd = EtcdClient.new
etcd.put("/queues/sched/ready/dc-8g-ut/wzd/test.1", {"job_id" => "test.1"})
etcd.put("/queues/sched/ready/dc-8g-ut/vip/test.2", {"job_id" => "test.2"})

queue = Queue.new
queue_name = "/queues/sched/ready/dc-8g-ut"
queue.init_queues([queue_name])

describe Queue do
  it "get_min_revision" do
    min_revision = queue.get_min_revision([queue_name])
    min_revision.nil?.should be_false
  end

  it "get_subqueue_set" do
    subqueues = queue.get_subqueue_set(queue_name)
    subqueues.should eq ["vip", "wzd"].to_set
  end

  it "pop_one_job" do
    job = queue.pop_one_job(queue_name, "wzd")
    job.not_nil!.key.should eq "/queues/sched/ready/dc-8g-ut/wzd/test.1"
  end

  it "queues_empty?" do
    queue.queues_empty?([queue_name]).should eq false
  end
end

etcd.delete("/queues/sched/ready/dc-8g-ut/wzd/test.1")
etcd.delete("/queues/sched/ready/dc-8g-ut/vip/test.2")
