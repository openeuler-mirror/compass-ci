require  "./resources"
require "../redis_client"
require "../elasticsearch_client"

module Scheduler
    module Monitor
        def self.updateJobStatus(hash : Hash, env : HTTP::Server::Context, resources : Scheduler::Resources)
            job_id = hash["job"]
            status = hash["job_state"].downcase
            if (job_id == nil) || (status == nil)
                return 0
            end

            client = resources.@redis_client.not_nil!
            case (status)
            when "running"
                # update job_id in running queue
                client.updateRunningInfo("#{job_id}", %({"process":"0%"}))
            when "post_run"
                # update job_id in running queue
                client.updateRunningInfo("#{job_id}", %({"process":"99%"}))
            when "finished"
                # remove job_id from running queue
                client.removeRunning("#{job_id}")
            else
                # OOM soft_timeout incomplete failed disturbed
                # downgrade_ucode microcode_is_not_matched load_disk_fail unknown_result_service error_mount
                #  miss_$result_fs manual_check
                # wget_kernel wget_kernel_fail wget_initrd wget_initrd_fail
                # nfs_hang initrd_broken booting kexec_fail
                # suspending_debug-$ite/$multi suspending-$ite/$multi suspending_debug-$i/$iterations suspending-$i/$iterations
                puts status
            end

            return 0
        end

        def self.updateJobParameter(hash : Hash, env : HTTP::Server::Context, resources : Scheduler::Resources)
            es = resources.@es_client.not_nil!
            job_id = hash["job"]
            if (job_id != nil)
                es.update("jobs/job", {hash.last_key => hash.last_value}, "#{job_id}")
            end
        end

        def self.guessJobId(remote_address : String, env : HTTP::Server::Context, resources : Scheduler::Resources)
            es = resources.@es_client.not_nil!
            redis = resources.@redis_client.not_nil!

            ip = remote_address.split(':')[0]
            hostname  = es.get_config("report/hostnames", remote_address)
            if hostname == nil
                hostname  = es.get_config("report/hostnames", "#{ip}")
            end

            if hostname
                return redis.findID(hostname.not_nil!)
            else
                return "0"
            end
        end
    end
end