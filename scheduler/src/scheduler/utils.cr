require  "./boot"
require  "./dequeue"
require  "../jobfile_operate"

# respon ipxe boot comand to qemu-runner
# - find the hostname (testbox) from qemu-runner's mac
# - find any job <job_id> that suite this testbox (testgroup-n)
# - use <job_id> to get <job.yaml> from es
# - use <lkp create-job-cpio.sh> to create job.cgz
# - respon ipxe boot comand
# 

module Scheduler
    module Utils
        def self.findJobBoot(mac : String, env : HTTP::Server::Context, resources : Scheduler::Resources)
            # client_address = env.request.remote_address
            es = resources.@es_client.not_nil!
            hostname = resources.@redis_client.not_nil!.@client.hget("mac2host", mac)
            job_id, error_code = "0", "0"
            job_id, error_code = Scheduler::Dequeue.responTestbox(hostname, env, resources, 10) if hostname
	    if job_id == "0"
		return Scheduler::Boot.ipxe_msg("No job now")
	    end

            # update job's  testbox property
            es.update("jobs/job", { "testbox" => hostname }, job_id)
	    # if get respon not a JSON::Any will raise exception
	    job_content = es.get("jobs/job", job_id)["_source"].as(JSON::Any)
            # create job.cgz before respon to ipxe parameter
            # should i use spawn { ? }
	    Jobfile::Operate.create_job_cpio(job_content, resources.@fsdir_root.not_nil!)
    
            # update es job.yaml at {#! queue option}
            # - update testbox: from mac,ip to host? {host-192-168-1-91}
            # - update tbox_group: {host-168-1}
    
            respon  = Scheduler::Boot.respon(job_content, env, resources)
        end
    end
end
