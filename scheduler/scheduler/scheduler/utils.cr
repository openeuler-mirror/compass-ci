require  "./boot"
require  "./dequeue"
require  "../jobfile_operate"

# respon ipxe boot comand to qemu-runner
# - find the hostname (testbox) from qemu-runner's mac
# - find any job <job_id> that suite this testbox (tbox_group-n)
# - use <job_id> to get <job.yaml> from es
# - use <lkp create-job-cpio.sh> to create job.cgz
# - respon ipxe boot comand
#

module Scheduler
    module Utils
        def self.find_job_boot(mac : String, env : HTTP::Server::Context, resources : Scheduler::Resources)
            # client_address = env.request.remote_address
            redis = resources.@redis_client.not_nil!
            hostname = redis.@client.hget("mac2host", mac)
            job_id  = "0"
            job_id, _ = Scheduler::Dequeue.respon_testbox(hostname, env, resources, 10) if hostname
            if job_id == "0"
                return Scheduler::Boot.ipxe_msg("No job now")
            end
            # update job's  testbox property
            job_content = JSON.parse(redis.get_job_content(job_id).not_nil!.to_json)
            # create job.cgz before respon to ipxe parameter
            # should i use spawn { ? }
            Jobfile::Operate.create_job_cpio(job_content, resources.@fsdir_root.not_nil!)

            # update es job.yaml at {#! queue option}
            # - update testbox: from mac,ip to host? {host-192-168-1-91}
            # - update tbox_group: {host-168-1}
            return Scheduler::Boot.respon(job_content, env, resources)
        end
    end
end
