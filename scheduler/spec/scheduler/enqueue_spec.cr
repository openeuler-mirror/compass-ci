require "spec"

require "../../src/redis_client"
require "../../src/scheduler/enqueue"
require "../../lib/kemal/src/kemal/ext/response"
require "../../lib/kemal/src/kemal/ext/context"

def createPostContext(hash : Hash)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    headers = HTTP::Headers { "content" => "application/json" }
    body = hash.to_json
    request = HTTP::Request.new("POST", "/submit_job", headers, body)
    context = HTTP::Server::Context.new(request, response)
    return context
end

describe Scheduler::Enqueue do

    describe "assign testbox | testgroup enqueue respon" do
        it "job has property testbox, but no test-group, save to testgroup_testbox queue" do
            context = createPostContext({ :testcase => "1234", :testbox => "myhost"})

            resources = Scheduler::Resources.new
            resources.redis_client("localhost", 6379)
            resources.es_client("localhost", 9200)
    
            # here test for testbox == testgroup
            raw_redis = Redis.new("localhost", 6379)
            job_list = "testbox_myhost"
            raw_redis.zremrangebyrank(job_list, 0, -1)
            job_list = "sched/jobs_to_run/myhost"
            raw_redis.zremrangebyrank(job_list, 0, -1)
    
            job_id, error_code = Scheduler::Enqueue.respon(context, resources)
            job_list = "sched/jobs_to_run/myhost"
            job_info = raw_redis.zrange(job_list, 0, -1, true)
            (job_id).should eq(job_info[0])

            job_list = "testbox_myhost"
            job_info = raw_redis.zrange(job_list, 0, -1, true)
            (job_info.size).should eq(0)
        end

        it "job has property testbox and test-group, save to sched/jobs_to_run/xxx queue not to testbox_xxx" do
            context = createPostContext({ :testcase => "1234", :testbox => "mygroup-1", "test-group" => "mygroup"})

            resources = Scheduler::Resources.new
            resources.redis_client("localhost", 6379)
            resources.es_client("localhost", 9200)
    
            raw_redis = Redis.new("localhost", 6379)
            job_list = "sched/jobs_to_run/mygroup"
            raw_redis.zremrangebyrank(job_list, 0, -1)
            job_list = "testbox_myhost"
            raw_redis.zremrangebyrank(job_list, 0, -1)
    
            job_id, error_code = Scheduler::Enqueue.respon(context, resources)
            job_list = "testbox_myhost"
            job_info_b = raw_redis.zrange(job_list, 0, -1, true)
            job_list = "sched/jobs_to_run/mygroup"
            job_info_g = raw_redis.zrange(job_list, 0, -1, true)

            (job_id).should eq(job_info_g[0])
            (job_info_b.size).should eq 0
        end
    end
end
