require "spec"
require "../../src/scheduler/monitor"
require "../../src/jobfile_operate"
require "../../src/constants"
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
    end
end
