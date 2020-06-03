require "spec"
require "../../src/scheduler/utils"
require "../../src/tools"

require "../../src/constants"

describe Scheduler::Utils do
    describe "ipxe boot for special testbox" do
        describe "if the runner has register hostname then find job in testgroup_[hostname] queue" do
            it "job_id = 0, respon no job" do
                mac = "52-54-00-12-34-56"
                remoteHostname = "testHost"
                remote_address = "127.0.0.1:5555"
                
                io = IO::Memory.new
		response = HTTP::Server::Response.new(io)
                request = HTTP::Request.new("GET", "/boot.ipxe/mac/#{mac}")

                raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
                raw_es_client.indices.delete({:index => "report"})

                raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
                pending_list = "sched/jobs_to_run/#{remoteHostname}"
                raw_redis.del(pending_list)
                pending_list = "testbox_#{remoteHostname}"
                raw_redis.del(pending_list)

                # request has remote_address
                request.remote_address = remote_address
                context = HTTP::Server::Context.new(request, response)

                resources = Scheduler::Resources.new
                resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
                resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)

                # registerer {mac => hostname}
                respon  = resources.@redis_client.not_nil!.@client.hset("mac2host", mac, remoteHostname)
    
                time_start = Time.utc
                respon = Scheduler::Utils.findJobBoot(mac, context, resources)
                time_stop = Time.utc
                timeLen = time_stop - time_start

                (timeLen.seconds).should eq 10
                respon.includes?("No job now").should be_true
            end
    
            it "job_id != 0, respon initrd kernel job in .cgz file with testbox == test-group" do
                job_id = "testjob"
                mac = "52-54-00-12-34-56"
                remoteHostname = "wfg-e595"
                remote_address = "127.0.0.1:5555"
                
		io = IO::Memory.new
                response = HTTP::Server::Response.new(io)
                request = HTTP::Request.new("GET", "/boot.ipxe/mac/#{mac}")

                raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
                raw_es_client.indices.delete({:index => "report"})
                raw_es_client.indices.delete({:index => "jobs"})

                raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
                pending_list = "sched/jobs_to_run/#{remoteHostname}"
                raw_redis.del(pending_list)
                raw_redis.del("sched/jobs_running")
                raw_redis.zadd(pending_list, "1.1", job_id)

                # request has remote_address
                request.remote_address = remote_address
                context = HTTP::Server::Context.new(request, response)

                resources = Scheduler::Resources.new
                resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
                resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)

                # register runner hostname
                respon  = resources.@redis_client.not_nil!.@client.hset("mac2host", mac, remoteHostname)

                # client testbox is  wfg-e595
                # job's testbox is   wfg-e595 

                # add testjob, this job contains { testbox: wfg-e595, tbox_group: wfg-e595}
                resources.fsdir_root("./public")
                resources.@es_client.not_nil!.add("/jobs/job", JSON.parse(DEMO_JOB).as_h, job_id)

                time_start = Time.utc
                respon = Scheduler::Utils.findJobBoot(mac, context, resources)
                time_stop = Time.utc
                timeLen = time_stop - time_start

                (timeLen.seconds).should eq 0

                respon_list = respon.split("\n")
                respon_list[0].should eq("#!ipxe")
                respon_list[2].should start_with("initrd")
                respon_list[respon_list.size - 2].should eq("boot")

                pending_list = "sched/jobs_to_run/#{remoteHostname}"
                respon = raw_redis.zrange(pending_list, 0, -1, true)
                (respon.size).should eq(0)
                respon = raw_redis.zrange("sched/jobs_running", 0, -1, true)
                (respon.size).should eq(2)

                # validate the testbox updated
                # raw_es_client (mybe use raw client is more real test)
                respon = resources.@es_client.not_nil!.get("/jobs/job", job_id)
                (respon["_source"]["testbox"]).should eq(remoteHostname)
            end

            it "job_id != 0, respon initrd kernel job in .cgz file with test-group != testbox" do
                job_id = "testjob"
                testgroup = "wfg-e595"
                mac = "52-54-00-12-34-56"
                remoteHostname = "wfg-e595-002"
                remote_address = "127.0.0.1:5555"
                
		io = IO::Memory.new
                response = HTTP::Server::Response.new(io)
                request = HTTP::Request.new("GET", "/boot.ipxe/mac/#{mac}")

                raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
                raw_es_client.indices.delete({:index => "report"})
                raw_es_client.indices.delete({:index => "jobs"})

                raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
                pending_list = "sched/jobs_to_run/#{testgroup}"
                raw_redis.del(pending_list)
                raw_redis.del("sched/jobs_running")
                raw_redis.del("sched/id2job")
                raw_redis.zadd(pending_list, "1.1", job_id)

                # request has remote_address
                request.remote_address = remote_address
                context = HTTP::Server::Context.new(request, response)

                resources = Scheduler::Resources.new
                resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
                resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)

                # register runner hostname
                respon  = resources.@redis_client.not_nil!.@client.hset("mac2host", mac, remoteHostname)
                
                # client testbox is  wfg-e595-002
                # job's testbox is   wfg-e595 

                # add testjob, this job contains { testbox: wfg-e595, tbox_group: wfg-e595}
                resources.fsdir_root("./public")
                resources.@es_client.not_nil!.add("/jobs/job", JSON.parse(DEMO_JOB).as_h, job_id)

                time_start = Time.utc
                respon = Scheduler::Utils.findJobBoot(mac, context, resources)
                time_stop = Time.utc
                timeLen = time_stop - time_start

                (timeLen.seconds).should eq 0

                respon_list = respon.split("\n")
                respon_list[0].should eq("#!ipxe")
                respon_list[2].should start_with("initrd")
                respon_list[respon_list.size - 2].should eq("boot")

                pending_list = "sched/jobs_to_run/#{testgroup}"
                respon = raw_redis.zrange(pending_list, 0, -1, true)
                (respon.size).should eq(0)
                respon = raw_redis.zrange("sched/jobs_running", 0, -1, true)
                (respon.size).should eq(2)

                respon = resources.@es_client.not_nil!.get("/jobs/job", job_id)
                (respon["_source"]["testbox"]).should eq(remoteHostname)
            end

            it "job_id != 0, respon initrd kernel job in .cgz file with test-group != testbox != client hostname" do
                job_id = "testjob"
                testgroup = "wfg-e595"
                mac = "52-54-00-12-34-56"
                remoteHostname = "wfg-e595-001"
                remote_address = "127.0.0.1:5555"
                
		io = IO::Memory.new
                response = HTTP::Server::Response.new(io)
                request = HTTP::Request.new("GET", "/boot.ipxe/mac/#{mac}")

                raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
                raw_es_client.indices.delete({:index => "report"})
                raw_es_client.indices.delete({:index => "jobs"})

                raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
                pending_list = "sched/jobs_to_run/#{testgroup}"
                raw_redis.del(pending_list)
                raw_redis.del("sched/jobs_running")
                raw_redis.zadd(pending_list, "1.1", job_id)

                # request has remote_address
                request.remote_address = remote_address
                context = HTTP::Server::Context.new(request, response)

                resources = Scheduler::Resources.new
                resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
                resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)

                # register runner hostname
                respon  = resources.@redis_client.not_nil!.@client.hset("mac2host", mac, remoteHostname)
                
                # client testbox is  wfg-e595-002
                # job's testbox is    wfg-e595-001

                # add testjob, this job contains { testbox: wfg-e595, tbox_group: wfg-e595}
                resources.fsdir_root("./public")
                json = JSON.parse(DEMO_JOB)
                json_hash = Public.hashReplaceWith(json.as_h, { "testbox" => "wfg-e595-002" })
                resources.@es_client.not_nil!.add("/jobs/job", json_hash, job_id)

                time_start = Time.utc
                respon = Scheduler::Utils.findJobBoot(mac, context, resources)
                time_stop = Time.utc
                timeLen = time_stop - time_start

                (timeLen.seconds).should eq 0

                respon_list = respon.split("\n")
                respon_list[0].should eq("#!ipxe")
                respon_list[2].should start_with("initrd")
                respon_list[respon_list.size - 2].should eq("boot")

                pending_list = "sched/jobs_to_run/#{testgroup}"
                respon = raw_redis.zrange(pending_list, 0, -1, true)
                (respon.size).should eq(0)
                respon = raw_redis.zrange("sched/jobs_running", 0, -1, true)
                (respon.size).should eq(2)

                respon = resources.@es_client.not_nil!.get("/jobs/job", job_id)
                (respon["_source"]["testbox"]).should eq(remoteHostname)
            end
        end
    end
end
