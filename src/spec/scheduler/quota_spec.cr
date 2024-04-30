require "spec"
require "lib/job_quota"
require "lib/etcd_client"
require "scheduler/constants"
require "scheduler/elasticsearch_client"

es = Elasticsearch::Client.new
es.create_subqueue({"subqueue" => "test-ut-1", "priority" => 9, "weight" => 20, "soft_quota" => 1, "hard_quota" => 3}, "test-ut-1")
sleep(1)
jq = JobQuota.new

etcd = EtcdClient.new
etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.1")
etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.2")
etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.3")
etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.4")


class TestJob
  getter hash : Hash(String, String)
  def initialize(job)
    @hash = job
  end
  METHOD_KEYS = %w(subqueue queue)
  macro method_missing(call)
    if METHOD_KEYS.includes?({{ call.name.stringify }})
      @hash[{{ call.name.stringify }}].to_s
    end
  end
end
job = TestJob.new({"queue" => "dc-8g-ut", "subqueue" => "test-ut-1"})

describe "hard_quota" do
  it "subqueue_jobs_qutoa" do
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.1", {"job_id" => "test.1"})
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.2", {"job_id" => "test.2"})
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.3", {"job_id" => "test.3"})
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.4", {"job_id" => "test.4"})

    expect_raises(Exception, /The maximum number of jobs/) do
      jq.subqueue_jobs_quota(job)
    end

    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.1")
    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.2")
    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.3")
    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.4")
  end
end

describe "total_quota" do
  it "total_jobs_qutoa" do
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.1", {"job_id" => "test.1"})
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.2", {"job_id" => "test.2"})
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.3", {"job_id" => "test.3"})
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.4", {"job_id" => "test.4"})

    expect_raises(Exception, /The maximum number of jobs/) do
      jq.total_jobs_quota(total_jobs_quota: 4)
    end

    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.1")
    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.2")
    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.3")
    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.4")
  end
end

describe "soft_quota" do
  it "subqueue_jobs_qutoa" do
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.1", {"job_id" => "test.1"})
    jq.subqueue_jobs_quota(job)
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.2", {"job_id" => "test.2"})
    jq.subqueue_jobs_quota(job)
    etcd.put("/queues/sched/ready/dc-8g-ut/test-ut-1/test.3", {"job_id" => "test.3"})

    expect_raises(Exception, /The maximum number of jobs/) do
      jq.total_jobs_quota(total_jobs_quota: 4)
    end

    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.1")
    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.2")
    etcd.delete("/queues/sched/ready/dc-8g-ut/test-ut-1/test.3")
  end
end



