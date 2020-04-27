require "kemal"
# require "kemal-basic-auth"

require "./configure"
require "./jobfile_operate"

require "./scheduler/utils"
require "./scheduler/boot"
require "./scheduler/dequeue"
require "./scheduler/enqueue"
require "./scheduler/resources"
require "./scheduler/diagnosis"
require "./scheduler/monitor"

# -------------------------------------------------------------------------------------------
# end_user:
# - use restful API [post "/queues"] to submit a job to scheduler
# -- json formated [job] in the request data
#  
# -------------------------------------------------------------------------------------------
# runner:
# - restful API [get /boot.ipxe/mac/52%3a54%3a00%3a12%3a34%3a56] to get a job for ipxe qemu-runner
#  -- when find then return <#!ipxe and job.cgz kernal initrd>
#  -- when no job return <#!ipxe no job messages>
#  -- if not find this qemu-runner's job, no need to get from global(default) queue
#
# - restful API [put "/report?hostname=myhostname&mac=ff:ff:ff:ff:ff:ff"] to report client's {mac => hostname}
# - restful API [get "/tmpfs/11/job.cgz"] to download job(11) job.cgz file
#  -- can ommit job.cgz : restful API [get "/tmpfs/11"] to download job(11) job.cgz file
#  
# - restful API [get "/getjob/:testbox"] to get a job from scheduler
#  -- not used yet
#  
# -------------------------------------------------------------------------------------------
# scheduler: 
# - use [redis incr] as job_id, a 64bit int number

module Scheduler
    VERSION = "0.1.0"

    # need parse from cmd line option?

    # get from local configure yaml file
    config = Configure::YamlFileOperate.new("./scheduler.yaml")

    resources = Scheduler::Resources.new
    resources.es_client(config.elasticSearchHost, config.elasticSearchPort)
    resources.redis_client(config.redisHost, config.redisPort)
    resources.qos(4, 10000)
    resources.fsdir_root(Kemal.config.public_folder)
    resources.test_params(%w(start_time end_time loadavg job_state))

    # disable basic authorize
    # basic_auth "username", "password"

    # echo alive
    get "/" do |env|
        "LKP Alive! The time is #{Time.local}"
    end

    # dequeue
    #  - echo job_id to caller
    #  -- job_id = "0" ? means no job find
    # maybe use this interface as "is there any job exists?"
    get  "/getjob/:testbox" do |env|
        job_id, error_code = Scheduler::Dequeue.respon(env, resources, 10)

        job_id
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
    post "/queues" do |env|
        job_id, error_code = Scheduler::Enqueue.respon(env, resources)

        job_id
    end

    # query job ?
    get "/queues" do |env|
    end

    # diagnosis server
    get "/diagnosis" do |env|
        Scheduler::Diagnosis.respon(env, resources)
    end

    # file down load server
    get "/tmpfs/:job_id/:job_package" do |env|
        job_id = env.params.url["job_id"]
        job_package = env.params.url["job_package"]
        file_path = ::File.join [resources.@fsdir_root, job_id, job_package]

        send_file env,  file_path
    end
    get "/tmpfs/:job_id" do |env|
        job_id = env.params.url["job_id"]
        file_path = ::File.join [resources.@fsdir_root, job_id, "job.cgz"]

        send_file env,  file_path
    end

    # client(runner) report its hostname and mac
    #  - when a runner pull jobs with it's mac infor, scheduler find out what hostname is it
    # /report?hostname=$hostname&mac=$mac (mac like ef:01:02:03:04:05)
    # add a <mac> => <hostname>
    # add a <ip> => <hostname>
    # add a <ip:port> => <hostname>
    # !!! how to do : two time calls with diffrent port. JUST use ip?
    # curl -X PUT "http://localhost:3000/report?hostname=wfg&mac=00-01-02-03-04-05"
    put "/report" do |env|
        client_address = env.request.remote_address

        if (client_hostname = env.params.query["hostname"]?)
            client_mac = env.params.query["mac"]?
            data = {:address => client_address, :hostname => client_hostname, :mac => client_mac}
            respon  = resources.@es_client.not_nil!.add_config("report/hostnames", data)

            "Done"
        else

            "No yet!"
        end
    end

    # client(runner) report job's status
    # /~lkp/cgi-bin/lkp-jobfile-append-var
    #  ?job_file=/lkp/scheduled/job.yaml&job_state=running
    #  ?job_file=/lkp/scheduled/job.yaml&job_state=post_run
    #  ?job_file=/lkp/scheduled/job.yaml&loadavg=0.28 0.82 0.49 1/105 3389&start_time=1587725398&end_time=1587725698
    get "/~lkp/cgi-bin/lkp-jobfile-append-var" do |env|
        client_address = env.request.remote_address

        # we should got the job_id from the request...
        job_id = "0"

        # try to guess the job_id
        # - env.params.query["job_id"]?
        # - guess from the client_address
        if job_id == "0"
            job_id = Scheduler::Monitor.guessJobId(client_address.not_nil!, env, resources)
        end

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

        "Done"
    end
    
    Kemal.run(3000)
end

# waiting lists:
# - query job
# - remove job
