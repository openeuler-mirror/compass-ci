# SPDX-License-Identifier: MulanPSL-2.0+

require "spec"

require "scheduler/constants"
require "scheduler/redis_client"
require "scheduler/scheduler/enqueue"
require "kemal/src/kemal/ext/response"
require "kemal/src/kemal/ext/context"

def create_post_context(hash : Hash)
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
            context = create_post_context({ :testcase => "1234", :testbox => "myhost"})

            resources = Scheduler::Resources.new
            resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
            resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)

            # here test for testbox == testgroup
            raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
            job_list = "testbox_myhost"
            raw_redis.zremrangebyrank(job_list, 0, -1)
            job_list = "sched/jobs_to_run/myhost"
            raw_redis.zremrangebyrank(job_list, 0, -1)

            job_id, _ = Scheduler::Enqueue.respon(context, resources)
            job_list = "sched/jobs_to_run/myhost"
            job_info = raw_redis.zrange(job_list, 0, -1, true)
            (job_id).should eq(job_info[0])

            job_list = "testbox_myhost"
            job_info = raw_redis.zrange(job_list, 0, -1, true)
            (job_info.size).should eq(0)
        end

        it "job has property testbox and test-group, save to sched/jobs_to_run/xxx queue not to testbox_xxx" do
            context = create_post_context({ :testcase => "1234", :testbox => "mygroup-1", "test-group" => "mygroup"})

            resources = Scheduler::Resources.new
            resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
            resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)

            raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
            job_list = "sched/jobs_to_run/mygroup"
            raw_redis.zremrangebyrank(job_list, 0, -1)
            job_list = "testbox_myhost"
            raw_redis.zremrangebyrank(job_list, 0, -1)

            job_id, _ = Scheduler::Enqueue.respon(context, resources)
            job_list = "testbox_myhost"
            job_info_b = raw_redis.zrange(job_list, 0, -1, true)
            job_list = "sched/jobs_to_run/mygroup"
            job_info_g = raw_redis.zrange(job_list, 0, -1, true)

            (job_id).should eq(job_info_g[0])
            (job_info_b.size).should eq 0
        end
    end
end
