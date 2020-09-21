# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "spec"
require "scheduler/scheduler/monitor"
require "scheduler/jobfile_operate"
require "scheduler/constants"
require "json"

def gen_put_context(url : String)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    headers = HTTP::Headers { "content" => "application/json" }
    request = HTTP::Request.new("PUT", url, headers)
    context = HTTP::Server::Context.new(request, response)
    return context
end

describe Scheduler::Monitor do
    describe "job maintain" do
        it "recieve job parameters, then update the job parameter in redis" do
            context = gen_put_context("/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=100&loadavg=0.28 0.82 0.49 1/105 3389&start_time=1587725398&end_time=1587725698")
            parameter_key = "start_time"

            # job_id =  context.request.query_params["job"]
            job_id = "100"
            parameter_value =  context.request.query_params[parameter_key]

            resources = Scheduler::Resources.new
            resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
            raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
            raw_redis.del("sched/id2job")

            # add 100, this job contains { testbox: wfg-e595, tbox_group: wfg-e595}
            resources.fsdir_root("./public")

            job_content = { "id" => job_id, parameter_key => parameter_value }
            Scheduler::Monitor.update_job_parameter(job_content, context, resources)

            response = resources.@redis_client.not_nil!.get_job_content(job_id)
            (response[parameter_key]).should eq("1587725398")
        end

        it "when job finished, update the job status" do
            context = gen_put_context("/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=1")
            job_id =  context.request.query_params["job_id"]

            running_queue = "sched/jobs_running"
            result_queue = "queue/extract_stats"
            job_info_queue = "sched/id2job"

            resources = Scheduler::Resources.new
            resources.es_client(JOB_ES_HOST,JOB_ES_PORT_DEBUG)
            resources.redis_client(JOB_REDIS_HOST,JOB_REDIS_PORT_DEBUG)

            raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
            raw_redis_client = Redis.new(JOB_REDIS_HOST,JOB_REDIS_PORT_DEBUG)

            raw_redis_client.del(running_queue)
            raw_redis_client.del(result_queue)
            raw_redis_client.hset(job_info_queue, job_id, "{\"testbox\" : \"test\", \"id\" : #{job_id}}")
            raw_redis_client.zrem(result_queue, job_id)
            priority_as_score = Time.local.to_unix_f
            raw_redis_client.zadd(running_queue, priority_as_score, job_id)
            raw_es_client.indices.delete({:index => "jobs"})
            resources.@es_client.not_nil!.set_job_content(JSON.parse(DEMO_JOB))

            Scheduler::Monitor.update_job_when_finished(job_id, resources)

            respon = resources.@es_client.not_nil!.get_job_content(job_id)
            (respon["testbox"]).should eq("test")
            (respon["id"]).should eq(job_id.to_i)

            running_job_count = raw_redis_client.zcount(running_queue, 0, -1)
            (running_job_count).should eq 0

            rusult_job = raw_redis_client.zrange(result_queue, 0, -1, true)
            (rusult_job[0]).should eq job_id

            job_info = raw_redis_client.hget(job_info_queue, job_id)
            job_info.should eq nil
        end
    end
end
