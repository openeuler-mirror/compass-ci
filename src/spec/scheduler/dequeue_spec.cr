# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "spec"

require "scheduler/constants"
require "scheduler/scheduler/resources"
require "scheduler/scheduler/dequeue"
require "kemal/src/kemal/ext/response"

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
            resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
            resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)

            raw_es = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
            raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)

            testbox = "tcm001"

            job_list = "sched/jobs_to_run/#{testbox}"
            raw_redis.del(job_list)

            # running_list = "sched/jobs_running" and job_info_list = "sched/id2job"
            raw_redis.del("sched/jobs_running")
            raw_redis.del("sched/id2job")

            raw_redis.zadd(job_list, "1.1", "1")
            raw_redis.zadd(job_list, "1.2", "2")

            job_json = JSON.parse({"testbox" => "#{testbox}"}.to_json)
            raw_es.create(
                 {
                     :index => "jobs",
                     :type => "_doc",
                     :id => "1",
                     :body => job_json
                 }
            )

            before_dequeue_time = Time.local.to_unix_f
            job_id, _ = Scheduler::Dequeue.respon_testbox(testbox, context, resources).not_nil!
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
            resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
            resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)

            raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)

            testbox = "tcm001"

            job_list = "sched/jobs_to_run/#{testbox}"
            raw_redis.del(job_list)
            raw_redis.del("sched/jobs_running")

            job_id, _ = Scheduler::Dequeue.respon_testbox(testbox, context, resources).not_nil!
            (job_id).should eq("0")

            # check redis data at running queue
            job_index_in_running = raw_redis.zrange("sched/jobs_running", 0, -1)
            (job_index_in_running.size).should eq(0)
        end

        it "raise exception, when es not has this job" do
            context = gen_context("/boot.ipxe/mac/ef-01-02-03-0f-ee")

            resources = Scheduler::Resources.new
            resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
            resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)

            raw_es = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
            raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)

            testbox = "tcm001"

            job_list = "sched/jobs_to_run/#{testbox}"
            raw_redis.del(job_list)

            # running_list = "sched/jobs_running" and job_info_list = "sched/id2job"
            raw_redis.del("sched/jobs_running")
            raw_redis.del("sched/id2job")

            raw_redis.zadd(job_list, "1.1", "1")
            raw_redis.zadd(job_list, "1.2", "2")

            # delete :index to make the specific exception raise
            raw_es.indices.delete({:index => "jobs"})

            begin
                Scheduler::Dequeue.respon_testbox(testbox, context, resources)
            rescue e: Exception
                (e.to_s).should eq("Invalid job (id=1) in es")
            end
        end
    end
end
