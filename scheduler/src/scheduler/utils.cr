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
            hostname  = es.get_config("report/hostnames", mac)

            job_id, error_code = "0", "0"
            case hostname
            when nil  # default testbox
                job_id, error_code = Scheduler::Dequeue.respon(env, resources, 10)
            else # special testbox
                job_id, error_code = Scheduler::Dequeue.responTestbox(hostname, env, resources, 10)

                # update job's  testbox property
                if job_id != "0"
                    es.update("jobs/job", { "testbox" => hostname }, job_id)
                end
            end

            # create job.cgz before respon to ipxe parameter
            # should i use spawn { ? }
            Jobfile::Operate.createJobPackage(job_id, resources)
    
            # update es job.yaml at {#! queue option}
            # - update testbox: from mac,ip to host? {host-192-168-1-91}
            # - update tbox_group: {host-168-1}
    
            respon  = Scheduler::Boot.respon(job_id, env, resources)
        end
    end
end
