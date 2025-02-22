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
  headers = HTTP::Headers{"content" => "application/json"}
  request = HTTP::Request.new("PUT", url, headers)
  context = HTTP::Server::Context.new(request, response)
  return context
end

describe Scheduler::Monitor do
  describe "job maintain" do

    it "when job finished, update the job status" do
      context = gen_put_context("/scheduler/lkp/post-run?job_file=/lkp/scheduled/job.yaml&job_id=1")
      job_id = context.request.query_params["job_id"]

      running_queue = "sched/jobs_running"
      result_queue = "queue/extract_stats"
      job_info_queue = "sched/id2job"

      resources = Scheduler::Resources.new
      resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)
      resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)

      raw_es_client = Elasticsearch::API::Client.new({:host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG})
      raw_redis_client = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)

      raw_redis_client.del(running_queue)
      raw_redis_client.del(result_queue)
      raw_redis_client.hset(job_info_queue, job_id, "{\"testbox\" : \"test\", \"id\" : #{job_id}}")
      raw_redis_client.zrem(result_queue, job_id)
      priority_as_score = Time.local.to_unix_f
      raw_redis_client.zadd(running_queue, priority_as_score, job_id)
      raw_es_client.indices.delete({:index => "jobs"})
      resources.@es_client.not_nil!.set_job_content(JSON.parse(DEMO_JOB))

      Scheduler::Monitor.update_job_when_finished(job_id, resources)

      respon = resources.@es_client.not_nil!.get_job(job_id)
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
