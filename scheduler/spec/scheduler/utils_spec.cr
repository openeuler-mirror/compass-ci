require "spec"
require "../../src/scheduler/utils"
require "../../src/tools"

describe Scheduler::Utils do
    describe "ipxe boot for special testbox" do
        describe "if the runner has regist hostname then find job in testgroup_[hostname] queue" do
            it "job_id = 0, respon no job", tags: "slow" do
                io = IO::Memory.new
                response = HTTP::Server::Response.new(io)
                request = HTTP::Request.new("GET", "/boot.ipxe/mac/52%3A54%3A00%3A12%3A34%3A56")

                remoteIP = "127.0.0.1"
                remotePort = 5555
                remoteHostname = "testHost"
                remote_address = "#{remoteIP}:#{remotePort}"

                raw_es_client = Elasticsearch::API::Client.new( { :host => "localhost", :port => 9200 } )
                raw_es_client.indices.delete({:index => "report"})

                raw_redis = Redis.new("localhost",  6379)
                pending_list = "testgroup_#{remoteHostname}"
                raw_redis.del(pending_list)
                pending_list = "testbox_#{remoteHostname}"
                raw_redis.del(pending_list)

                # request has remote_address
                request.remote_address = remote_address
                context = HTTP::Server::Context.new(request, response)

                resources = Scheduler::Resources.new
                resources.redis_client("localhost", 6379)
                resources.es_client("localhost", 9200)

                # regist runner { ip:port => hostname }
                # maybe only { ip => hostname } || { mac => hostname } is valid
                data = {:address => remote_address, :hostname => remoteHostname, :mac => nil}
                respon  = resources.@es_client.not_nil!.add_config("report/hostnames", data)
    
                time_start = Time.utc
                respon = Scheduler::Utils.findJobBoot(remote_address, context, resources)
                time_stop = Time.utc
                timeLen = time_stop - time_start

                (timeLen.seconds).should eq 10
                respon.should eq("#!ipxe\n\necho ...\necho No job now\necho ...\nreboot\n")
            end
    
            it "job_id != 0, respon initrd kernel job in .cgz file with testbox == test-group" do
                io = IO::Memory.new
                response = HTTP::Server::Response.new(io)
                request = HTTP::Request.new("GET", "/boot.ipxe/mac/52%3A54%3A00%3A12%3A34%3A56")

                remoteIP = "127.0.0.1"
                remotePort = 5555
                remoteHostname = "wfg-e595"
                remote_address = "#{remoteIP}:#{remotePort}"
                job_id = "testjob"
                mac = "52:54:00:12:34:56"

                raw_es_client = Elasticsearch::API::Client.new( { :host => "localhost", :port => 9200 } )
                raw_es_client.indices.delete({:index => "report"})
                raw_es_client.indices.delete({:index => "jobs"})

                raw_redis = Redis.new("localhost",  6379)
                pending_list = "testgroup_#{remoteHostname}"
                raw_redis.del(pending_list)
                raw_redis.del("running")
                raw_redis.zadd(pending_list, "1.1", job_id)

                # request has remote_address
                request.remote_address = remote_address
                context = HTTP::Server::Context.new(request, response)

                resources = Scheduler::Resources.new
                resources.redis_client("localhost", 6379)
                resources.es_client("localhost", 9200)

                # regist runner hostname
                data = { :address => remote_address, :hostname => remoteHostname, :mac => mac }
                respon  = resources.@es_client.not_nil!.add_config("report/hostnames", data)

                # client testbox is  wfg-e595
                # job's testbox is    wfg-e595 

                # add testjob, this job contains { testbox: wfg-e595, tbox_group: wfg-e595}
                resources.fsdir_root("/home/chief/code/crcode/scheduler/public")
                json = JSON.parse(Jobfile::Operate.load_yaml("test/demo_job.yaml").to_json)
                resources.@es_client.not_nil!.add("/jobs/job", json.as_h, job_id)

                time_start = Time.utc
                respon = Scheduler::Utils.findJobBoot(mac, context, resources)
                time_stop = Time.utc
                timeLen = time_stop - time_start

                (timeLen.seconds).should eq 0

                respon_list = respon.split("\n")
                respon_list[0].should eq("#!ipxe")
                respon_list[2].should start_with("initrd")
                respon_list[respon_list.size - 2].should eq("boot")

                pending_list = "testgroup_#{remoteHostname}"
                respon = raw_redis.zrange(pending_list, 0, -1, true)
                (respon.size).should eq(0)
                respon = raw_redis.zrange("running", 0, -1, true)
                (respon.size).should eq(2)

                # validate the testbox updated
                # raw_es_client (mybe use raw client is more real test)
                respon = resources.@es_client.not_nil!.get("/jobs/job", job_id)
                (respon["_source"]["testbox"]).should eq(remoteHostname)
            end

            it "job_id != 0, respon initrd kernel job in .cgz file with test-group != testbox" do
                io = IO::Memory.new
                response = HTTP::Server::Response.new(io)
                request = HTTP::Request.new("GET", "/boot.ipxe/mac/52%3A54%3A00%3A12%3A34%3A56")

                remoteIP = "127.0.0.1"
                remotePort = 5555
                remoteHostname = "wfg-e595-002"
                testgroup = "wfg-e595"
                remote_address = "#{remoteIP}:#{remotePort}"
                job_id = "testjob"
                mac = "52:54:00:12:34:56"

                raw_es_client = Elasticsearch::API::Client.new( { :host => "localhost", :port => 9200 } )
                raw_es_client.indices.delete({:index => "report"})
                raw_es_client.indices.delete({:index => "jobs"})

                raw_redis = Redis.new("localhost",  6379)
                pending_list = "testgroup_#{testgroup}"
                raw_redis.del(pending_list)
                raw_redis.del("running")
                raw_redis.del("hi_running")
                raw_redis.zadd(pending_list, "1.1", job_id)

                # request has remote_address
                request.remote_address = remote_address
                context = HTTP::Server::Context.new(request, response)

                resources = Scheduler::Resources.new
                resources.redis_client("localhost", 6379)
                resources.es_client("localhost", 9200)

                # regist runner hostname
                data = { :address => remote_address, :hostname => remoteHostname, :mac => mac }
                respon  = resources.@es_client.not_nil!.add_config("report/hostnames", data)
                
                # client testbox is  wfg-e595-002
                # job's testbox is    wfg-e595 

                # add testjob, this job contains { testbox: wfg-e595, tbox_group: wfg-e595}
                resources.fsdir_root("/home/chief/code/crcode/scheduler/public")
                json = JSON.parse(Jobfile::Operate.load_yaml("test/demo_job.yaml").to_json)
                resources.@es_client.not_nil!.add("/jobs/job", json.as_h, job_id)

                time_start = Time.utc
                respon = Scheduler::Utils.findJobBoot(mac, context, resources)
                time_stop = Time.utc
                timeLen = time_stop - time_start

                (timeLen.seconds).should eq 0

                respon_list = respon.split("\n")
                respon_list[0].should eq("#!ipxe")
                respon_list[2].should start_with("initrd")
                respon_list[respon_list.size - 2].should eq("boot")

                pending_list = "testgroup_#{testgroup}"
                respon = raw_redis.zrange(pending_list, 0, -1, true)
                (respon.size).should eq(0)
                respon = raw_redis.zrange("running", 0, -1, true)
                (respon.size).should eq(2)

                respon = resources.@es_client.not_nil!.get("/jobs/job", job_id)
                (respon["_source"]["testbox"]).should eq(remoteHostname)
            end

            it "job_id != 0, respon initrd kernel job in .cgz file with test-group != testbox != client hostname" do
                io = IO::Memory.new
                response = HTTP::Server::Response.new(io)
                request = HTTP::Request.new("GET", "/boot.ipxe/mac/52%3A54%3A00%3A12%3A34%3A56")

                remoteIP = "127.0.0.1"
                remotePort = 5555
                remoteHostname = "wfg-e595-001"
                testgroup = "wfg-e595"
                remote_address = "#{remoteIP}:#{remotePort}"
                job_id = "testjob"
                mac = "52:54:00:12:34:56"

                raw_es_client = Elasticsearch::API::Client.new( { :host => "localhost", :port => 9200 } )
                raw_es_client.indices.delete({:index => "report"})
                raw_es_client.indices.delete({:index => "jobs"})

                raw_redis = Redis.new("localhost",  6379)
                pending_list = "testgroup_#{testgroup}"
                raw_redis.del(pending_list)
                raw_redis.del("running")
                raw_redis.zadd(pending_list, "1.1", job_id)

                # request has remote_address
                request.remote_address = remote_address
                context = HTTP::Server::Context.new(request, response)

                resources = Scheduler::Resources.new
                resources.redis_client("localhost", 6379)
                resources.es_client("localhost", 9200)

                # regist runner hostname
                data = { :address => remote_address, :hostname => remoteHostname, :mac => mac }
                respon  = resources.@es_client.not_nil!.add_config("report/hostnames", data)
                
                # client testbox is  wfg-e595-002
                # job's testbox is    wfg-e595-001

                # add testjob, this job contains { testbox: wfg-e595, tbox_group: wfg-e595}
                resources.fsdir_root("/home/chief/code/crcode/scheduler/public")
                json = JSON.parse(Jobfile::Operate.load_yaml("test/demo_job.yaml").to_json)
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

                pending_list = "testgroup_#{testgroup}"
                respon = raw_redis.zrange(pending_list, 0, -1, true)
                (respon.size).should eq(0)
                respon = raw_redis.zrange("running", 0, -1, true)
                (respon.size).should eq(2)

                respon = resources.@es_client.not_nil!.get("/jobs/job", job_id)
                (respon["_source"]["testbox"]).should eq(remoteHostname)
            end
        end
    end
end
