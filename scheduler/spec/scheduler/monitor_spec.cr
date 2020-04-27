require "spec"
require "../../src/scheduler/monitor"
require "../../src/jobfile_operate"

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
    describe "status maintain" do
        it "recieve running, then update the running job status" do
            context = gen_put_context("/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_state=running")
            parameter_key = "job_state"

            # job_id =  context.request.query_params["job"]
            job_id = "testjob"
            job_status =  context.request.query_params[parameter_key]

            resources = Scheduler::Resources.new
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)
            job_list = "running"
            hi_job_list = "hi_running"
            raw_redis.del(job_list)
            raw_redis.del(hi_job_list)

            priorityAsScore = Time.local.to_unix_f
            raw_redis.zadd(job_list, priorityAsScore, job_id)
            raw_redis.hset(hi_job_list, job_id, %({"testbox":"tcm-001"}))

            hash = { "job" => job_id, parameter_key => job_status }
            respon = Scheduler::Monitor.updateJobStatus(hash, context, resources)

            respon = raw_redis.hget(hi_job_list, job_id)
            respon =JSON.parse(respon.not_nil!)
            (respon["testbox"]).should eq("tcm-001")
            (respon["process"]).should eq("0%")
        end

        it "recieve post_run report, then update the running job status" do
            context = gen_put_context("/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_state=post_run")
            parameter_key = "job_state"

            # job_id =  context.request.query_params["job"]
            job_id = "testjob"
            job_status =  context.request.query_params[parameter_key]

            resources = Scheduler::Resources.new
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)
            job_list = "running"
            hi_job_list = "hi_running"
            raw_redis.del(job_list)
            raw_redis.del(hi_job_list)

            priorityAsScore = Time.local.to_unix_f
            raw_redis.zadd(job_list, priorityAsScore, job_id)
            raw_redis.hset(hi_job_list, job_id, %({"testbox":"tcm-001"}))

            hash = { "job" => job_id, parameter_key => job_status }
            respon = Scheduler::Monitor.updateJobStatus(hash, context, resources)

            respon = raw_redis.hget(hi_job_list, job_id)
            respon =JSON.parse(respon.not_nil!)
            (respon["testbox"]).should eq("tcm-001")
            (respon["process"]).should eq("99%")
        end

        it "recieve finished, then remove from the running queue" do
            context = gen_put_context("/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_state=finished")
            parameter_key = "job_state"

            # job_id =  context.request.query_params["job"]
            job_id = "testjob"
            job_status =  context.request.query_params[parameter_key]

            resources = Scheduler::Resources.new
            resources.redis_client("localhost", 6379)

            raw_redis = Redis.new("localhost", 6379)
            job_list = "running"
            hi_job_list = "hi_running"
            raw_redis.del(job_list)
            raw_redis.del(hi_job_list)

            priorityAsScore = Time.local.to_unix_f
            raw_redis.zadd(job_list, priorityAsScore, job_id)
            raw_redis.hset(hi_job_list, job_id, %({"testbox":"tcm-001"}))

            hash = { "job" => job_id, parameter_key => job_status }
            respon = Scheduler::Monitor.updateJobStatus(hash, context, resources)

            respon = raw_redis.zrank(job_list, job_id)
            respon.should be_nil
            respon = raw_redis.hget(hi_job_list, job_id)
            respon.should be_nil
        end

        it "recieve process report, but the not find the job_id in queue..." do
        end
    end

    describe "job maintain" do
        it "recieve job parameters, then update the job parametre" do
            context = gen_put_context("/~lkp/cgi-bin/lkp-jobfile-append-var??job_file=/lkp/scheduled/job.yaml&loadavg=0.28 0.82 0.49 1/105 3389&start_time=1587725398&end_time=1587725698")
            parameter_key = "start_time"

            # job_id =  context.request.query_params["job"]
            job_id = "testjob"
            parameter_value =  context.request.query_params[parameter_key]

            resources = Scheduler::Resources.new
            resources.es_client("localhost", 9200)

            # add testjob, this job contains { testbox: wfg-e595, tbox_group: wfg-e595}
            resources.fsdir_root("/home/chief/code/crcode/scheduler/public")

            raw_es_client = Elasticsearch::API::Client.new( { :host => "localhost", :port => 9200 } )
            # raw_es_client.indices.delete({:index => "report"})
            raw_es_client.indices.delete({:index => "jobs"})

            json = JSON.parse(Jobfile::Operate.load_yaml("test/demo_job.yaml").to_json)
            json_hash = Public.hashReplaceWith(json.as_h, { "testbox" => "wfg-e595-001" })
            resources.@es_client.not_nil!.add("/jobs/job", json_hash, job_id)
            
            hash = { "job" => job_id, parameter_key => parameter_value }
            Scheduler::Monitor.updateJobParameter(hash, context, resources)

            respon = resources.@es_client.not_nil!.get("jobs/job", job_id)
            (respon["_source"][parameter_key]).should eq("1587725398")
        end
    end

    # merge just like cover
    describe "learning hash merge" do
        it "test ", tags: "learning" do
            json_a = JSON.parse(%({"testbox":"tcm01"}))
            json_b = JSON.parse(%({"testbox":"tcm02"}))
            (json_a.as_h.merge(json_b.as_h)["testbox"]).should eq("tcm02")

            json_a = JSON.parse(%({"testbox":"tcm01"}))
            json_b = JSON.parse(%({"testbox2":"tcm02"}))
            (json_a.as_h.merge(json_b.as_h)["testbox"]).should eq("tcm01")
            (json_a.as_h.merge(json_b.as_h)["testbox2"]).should eq("tcm02")

            json_a = JSON.parse(%({"testbox":"tcm01", "testbox2":[{"testname":"testvalue", "testname2":"testvalue2"}]}))
            json_b = JSON.parse(%({"testbox2":[{"testname":"testvalue2"}]}))
            (json_a.as_h.merge(json_b.as_h)["testbox"]).should eq("tcm01")
            (json_a.as_h.merge(json_b.as_h)["testbox2"]).should eq([{"testname" => "testvalue2"}])
        end
    end
end
