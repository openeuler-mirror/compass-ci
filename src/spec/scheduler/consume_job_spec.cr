require "spec"
require "scheduler/consume_job"


etcd = EtcdClient.new
etcd.put("/queues/sched/ready/dc-8g-ut/wzd/test.1", {"job_id" => "test.1"})
etcd.put("/queues/sched/ready/dc-8g-ut/vip/test.2", {"job_id" => "test.2"})

es = Elasticsearch::Client.new
es.create_subqueue({"subqueue" => "wzd", "priority" => 9, "weight" => 20}, "wzd")
es.create_subqueue({"subqueue" => "vip", "priority" => 0, "weight" => 100}, "vip")
sleep(1)

queues = ["/queues/sched/ready/dc-8g-ut"]

describe ConsumeJob do
  it "consume_history_job" do
    queue_instance = Queue.instance
    queue_instance.init_queues(queues)
    job, state = ConsumeJob.new.consume_history_job(queues)
    job.not_nil!.key.should eq "/queues/sched/ready/dc-8g-ut/vip/test.2"
    state.nil?.should be_true

    etcd.delete("/queues/sched/ready/dc-8g-ut/wzd/test.1")
    etcd.delete("/queues/sched/ready/dc-8g-ut/vip/test.2")
    etcd.delete("/queues/sched/in_process/dc-8g-ut/wzd/test.1")
    etcd.delete("/queues/sched/in_process/dc-8g-ut/vip/test.2")
  end
end
