require "kemal"


require "./jobfile_operate"

require "./scheduler/utils"
require "./scheduler/boot"
require "./scheduler/dequeue"
require "./scheduler/enqueue"
require "./scheduler/resources"
require "./scheduler/monitor"

# -------------------------------------------------------------------------------------------
# end_user:
# - restful API [post "/submit_job"] to submit a job to scheduler
# -- json formated [job] in the request data
#  
# -------------------------------------------------------------------------------------------
# runner:
# - restful API [get "/boot.ipxe/mac/52-54-00-12-34-56"] to get a job for ipxe qemu-runner
#  -- when find then return <#!ipxe and job.cgz kernal initrd>
#  -- when no job return <#!ipxe no job messages>
#
# - restful API [put "/set_host_mac?hostname=myhostname&mac=ff-ff-ff-ff-ff-ff"] to report testbox's {mac => hostname}
# - restful API [get "/tmpfs/11/job.cgz"] to download job(11) job.cgz file
# - restful API [get "/~lkp/cgi-bin/lkp-jobfile-append-var"] report job var that should be append
# 
# -------------------------------------------------------------------------------------------
# scheduler: 
# - use [redis incr] as job_id, a 64bit int number
# - restful API [get "/"] default echo
#
module Scheduler
    VERSION = "0.1.0"
    
    JOB_REDIS_HOST = "172.17.0.1"
    JOB_REDIS_PORT = 6379

    JOB_ES_HOST = "172.17.0.1"
    JOB_ES_PORT = 9200


    resources = Scheduler::Resources.new
    resources.es_client(JOB_ES_HOST, JOB_ES_PORT)
    resources.redis_client(JOB_REDIS_HOST, JOB_REDIS_PORT)
    resources.fsdir_root(Kemal.config.public_folder)
    resources.test_params(%w(start_time end_time loadavg job_state))

    # echo alive
    get "/" do |env|
        "LKP Alive! The time is #{Time.local}"
    end

    # for XXX_runner get job
    #
    # /boot.ipxe/mac/${mac} 
    # /boot.xxx/host/${hostname}
    # /boot.yyy/mac/${mac}
    get "/boot.:boot_type/:parameter/:value" do |env|
        bt = env.params.url["boot_type"]
        pm = env.params.url["parameter"]
        va = env.params.url["value"]

        respon = Scheduler::Utils.findJobBoot(va, env, resources)
    end

    # enqueue
    #  - echo job_id to caller
    #  -- job_id = "0" ? means failed
    post "/submit_job" do |env|
        job_id, error_code = Scheduler::Enqueue.respon(env, resources)

        job_id
    end

    # file down load server
    get "/tmpfs/:job_id/:job_package" do |env|
        job_id = env.params.url["job_id"]
        job_package = env.params.url["job_package"]
        file_path = ::File.join [resources.@fsdir_root, job_id, job_package]

        send_file env,  file_path
    end

    # client(runner) report its hostname and mac
    #  - when a runner pull jobs with it's mac infor, scheduler find out what hostname is it
    # /set_host_mac?hostname=$hostname&mac=$mac (mac like ef:01:02:03:04:05)
    # add a <mac> => <hostname>
    # add a <ip> => <hostname>
    # add a <ip:port> => <hostname>
    # !!! how to do : two time calls with diffrent port. JUST use ip?
    # curl -X PUT "http://localhost:3000/set_host_mac?hostname=wfg&mac=00-01-02-03-04-05"
    put "/set_host_mac" do |env|
        client_address = env.request.remote_address

        if (client_hostname = env.params.query["hostname"]?)
            client_mac = env.params.query["mac"]?
            data = {:address => client_address, :hostname => client_hostname, :mac => client_mac}
            respon  = resources.@es_client.not_nil!.add_config("set_host_mac/hostnames", data)

            "Done"
        else

            "No yet!"
        end
    end

    # client(runner) report job's status
    # /~lkp/cgi-bin/lkp-jobfile-append-var
    #  ?job_file=/lkp/scheduled/job.yaml&job_state=running&job_id=10
    #  ?job_file=/lkp/scheduled/job.yaml&job_state=post_run&job_id=10
    #  ?job_file=/lkp/scheduled/job.yaml&loadavg=0.28 0.82 0.49 1/105 3389&start_time=1587725398&end_time=1587725698&job_id=10
    get "/~lkp/cgi-bin/lkp-jobfile-append-var" do |env|
        # get job_id from the request
        job_id = env.params.query["job_id"]?
        if job_id
            # try to get report value and then update it
            resources.@test_params.not_nil!.each do |parameter|
                # update in es (job content)
                if (value = env.params.query[parameter]?)
                    Scheduler::Monitor.updateJobParameter({ "job" => job_id,  parameter => value }, env, resources)

                    # update in redis (job runing status)
                    if (parameter == "job_state")
                        Scheduler::Monitor.updateJobParameter({ "job" => job_id,  parameter => value }, env, resources)
                    end
                end
            end
        end

        "Done"
    end
    
    Kemal.run(3000)
end

