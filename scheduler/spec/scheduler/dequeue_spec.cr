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
    # there has pending testgroup queue
    # testbox search the job in testgroup, testbox => testgroup[-n]
    describe "testbox queue dequeue respon" do
        it "return job_id > 0, when find a pending job in special testbox queue" do
            context = gen_context("/boot.ipxe/mac/ef-01-02-03-0f-ee")

            resources = Scheduler::Resources.new
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)

            testbox = "tcm001"

            job_list = "sched/jobs_to_run/#{testbox}"
            raw_redis.del(job_list)

            # running_list = "sched/jobs_running" and job_info_list = "sched/id2job"
            raw_redis.del("sched/jobs_running")
            raw_redis.del("sched/id2job")

            raw_redis.zadd(job_list, "1.1", "1")
            raw_redis.zadd(job_list, "1.2", "2")

            before_dequeue_time = Time.local.to_unix_f
            job_id, error_code = Scheduler::Dequeue.responTestbox(testbox, context, resources).not_nil!
            (job_id).should eq("1")

            # check redis data at pending queue
            first_job = raw_redis.zrange(job_list, 0, 0)
            (first_job[0]).should  eq("2")
            
            # check redis data at running queue
            job_index_in_running = raw_redis.zrank("sched/jobs_running", job_id)
            running_job = raw_redis.zrange("sched/jobs_running", job_index_in_running, job_index_in_running, true)
            (running_job[1].to_s.to_f64).should be_close(before_dequeue_time, 0.1)

            # check append info
            append_info = raw_redis.hget("sched/id2job", job_id)
            respon =JSON.parse(append_info.not_nil!)
            (respon["testbox"]).should eq("tcm001")
        end

        it "return job_id = 0, when there has no this testbox (testgroup) queue" do
            context = gen_context("/boot.ipxe/mac/ef-01-02-03-0f-ee")

            resources = Scheduler::Resources.new
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)

            testbox = "tcm001"

            job_list = "sched/jobs_to_run/#{testbox}"
            raw_redis.del(job_list)
            raw_redis.del("sched/jobs_running")

            before_dequeue_time = Time.local.to_unix_f
            job_id, error_code = Scheduler::Dequeue.responTestbox(testbox, context, resources).not_nil!
            (job_id).should eq("0")

            # check redis data at running queue
            job_index_in_running = raw_redis.zrange("sched/jobs_running", 0, -1)
            (job_index_in_running.size).should eq(0) 
        end
    end
end

