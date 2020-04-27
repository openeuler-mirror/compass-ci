require "spec"

require "../../src/scheduler/resources"
require "../../src/scheduler/dequeue"
require "../../lib/kemal/src/kemal/ext/response"

def gen_context(url : String)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    headers = HTTP::Headers { "content" => "application/json" }
    request = HTTP::Request.new("GET", url, headers)
    context = HTTP::Server::Context.new(request, response)
    return context
end

describe Scheduler::Dequeue do

    describe "global queue dequeue respon" do
        it "return job_id > 0, when find a pending job in single queue" do
            context = gen_context("/getjob/testbox")

            resources = Scheduler::Resources.new
            resources.qos(1, 1)
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)
            job_list = "sorted_job_list_0"
            raw_redis.zadd(job_list, "1.1", "1")
            raw_redis.zadd(job_list, "1.2", "2")

            before_dequeue_time = Time.local.to_unix_f
            job_id, error_code = Scheduler::Dequeue.respon(context, resources)
            (job_id).should eq("1")

            # check redis data at pending queue
            first_job = raw_redis.zrange(job_list, 0, 0)
            (first_job[0]).should  eq("2")
            
            # check redis data at running queue
            job_index_in_running = raw_redis.zrank("running", job_id)
            running_job = raw_redis.zrange("running", job_index_in_running, job_index_in_running, true)

            (running_job[1].to_s.to_f64).should be_close(before_dequeue_time, 0.1)
        end

        it "return job_id > 0, when find a pending job in second queue" do
            context = gen_context("/getjob/testbox")

            resources = Scheduler::Resources.new
            resources.qos(2, 10)
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)

            # remove any job in queue 1
            job_list = "sorted_job_list_0"
            raw_redis.zremrangebyrank(job_list, 0, -1)

            # add 2 job to queue 2
            job_list = "sorted_job_list_1"
            raw_redis.zadd(job_list, "1.1", "1")
            raw_redis.zadd(job_list, "1.2", "2")

            before_dequeue_time = Time.local.to_unix_f

            job_id, error_code = Scheduler::Dequeue.respon(context, resources)
            (job_id).should eq("1")

            # check redis data at pending queue
            first_job = raw_redis.zrange(job_list, 0, 0)
            (first_job[0]).should  eq("2")
            
            # check redis data at running queue
            job_index_in_running = raw_redis.zrank("running", job_id)
            running_job = raw_redis.zrange("running", job_index_in_running, job_index_in_running, true)

            (running_job[1].to_s.to_f64).should be_close(before_dequeue_time, 0.1)
        end

        it "return job_id = 0, when there has no job" do
            context = gen_context("/getjob/testbox")

            resources = Scheduler::Resources.new
            resources.qos(1, 11)
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)
            job_list = "sorted_job_list_0"
            raw_redis.zremrangebyrank(job_list, 0, -1)

            job_id, error_code = Scheduler::Dequeue.respon(context, resources)
            (job_id).should eq("0")
        end
    end

    # there has pending testgroup queue
    # testbox search the job in testgroup, testbox => testgroup[-n]
    describe "testbox queue dequeue respon" do
        it "return job_id > 0, when find a pending job in special testbox queue" do
            context = gen_context("/boot.ipxe/mac/ef%3A01%3A02%3A03%3A0f%3Aee")

            resources = Scheduler::Resources.new
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)

            testbox = "tcm001"

            job_list = "testgroup_#{testbox}"
            raw_redis.del(job_list)

            # running_list = "running" and running_info_list = "hi_running"
            raw_redis.del("running")
            raw_redis.del("hi_running")

            raw_redis.zadd(job_list, "1.1", "1")
            raw_redis.zadd(job_list, "1.2", "2")

            before_dequeue_time = Time.local.to_unix_f
            job_id, error_code = Scheduler::Dequeue.responTestbox(testbox, context, resources)
            (job_id).should eq("1")

            # check redis data at pending queue
            first_job = raw_redis.zrange(job_list, 0, 0)
            (first_job[0]).should  eq("2")
            
            # check redis data at running queue
            job_index_in_running = raw_redis.zrank("running", job_id)
            running_job = raw_redis.zrange("running", job_index_in_running, job_index_in_running, true)
            (running_job[1].to_s.to_f64).should be_close(before_dequeue_time, 0.1)

            # check append info
            append_info = raw_redis.hget("hi_running", job_id)
            respon =JSON.parse(append_info.not_nil!)
            (respon["testbox"]).should eq("tcm001")
        end

        it "return job_id = 0, when there has no this testbox (testgroup) queue" do
            context = gen_context("/boot.ipxe/mac/ef%3A01%3A02%3A03%3A0f%3Aee")

            resources = Scheduler::Resources.new
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)

            testbox = "tcm001"

            job_list = "testgroup_#{testbox}"
            raw_redis.del(job_list)
            raw_redis.del("running")

            before_dequeue_time = Time.local.to_unix_f
            job_id, error_code = Scheduler::Dequeue.responTestbox(testbox, context, resources)
            (job_id).should eq("0")

            # check redis data at running queue
            job_index_in_running = raw_redis.zrange("running", 0, -1)
            (job_index_in_running.size).should eq(0) 
        end
    end
end

# default MOCKS runs failed
# require "mocks/spec"
#  - /usr/share/crystal/src/hash.cr:907:18
#  - 907 | hash = key.object_id.hash.to_u32!
#  - Error: protected method 'object_id' called for Mocks::Registry::LastArgsKey

#dependencies:
#   mocks:
#    github: waterlink/mocks.cr