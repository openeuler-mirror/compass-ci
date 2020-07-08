require "kemal"


require "./jobfile_operate"

require "./scheduler/utils"
require "./scheduler/boot"
require "./scheduler/dequeue"
require "./scheduler/enqueue"
require "./scheduler/resources"
require "./scheduler/monitor"
require "./constants.cr"
require "../lib/sched"

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
# - restful API [get "/job_initrd_tmpfs/11/job.cgz"] to download job(11) job.cgz file
# - restful API [get "/~lkp/cgi-bin/lkp-jobfile-append-var"] report job var that should be append
# - restful API [get "/~lkp/cgi-bin/lkp-post-run" ] to move job from redis queue "sched/jobs_running" to "sched/extract_stats" and remove job from redis queue "sched/id2job"
#
# -------------------------------------------------------------------------------------------
# scheduler:
# - use [redis incr] as job_id, a 64bit int number
# - restful API [get "/"] default echo
#
module Scheduler
    VERSION = "0.1.1"

    sched = Sched.new

    redis_host = (ENV.has_key?("REDIS_HOST") ? ENV["REDIS_HOST"] : JOB_REDIS_HOST)
    redis_port = (ENV.has_key?("REDIS_PORT") ? ENV["REDIS_PORT"] : JOB_REDIS_PORT).to_i32

    es_host = (ENV.has_key?("ES_HOST") ? ENV["ES_HOST"] : JOB_ES_HOST)
    es_port = (ENV.has_key?("ES_PORT") ? ENV["ES_PORT"] : JOB_ES_PORT).to_i32

    resources = Scheduler::Resources.new
    resources.es_client(es_host, es_port)
    resources.redis_client(redis_host, redis_port)
    resources.fsdir_root(Kemal.config.public_folder)
    resources.test_params(%w(start_time end_time loadavg job_state))

    # for debug (maybe kemal debug|logger does better)
    def self.debug_message(env, respon)
        puts ">> #{env.request.remote_address}"
        puts "<< #{respon}"
        puts ""
    end

    # echo alive
    get "/" do | _ |
        "LKP Alive! The time is #{Time.local}, version = #{VERSION}"
    end

    # for XXX_runner get job
    #
    # /boot.ipxe/mac/${mac}
    # /boot.xxx/host/${hostname}
    # /boot.yyy/mac/${mac}
    get "/boot.:boot_type/:parameter/:value" do |env|
        va = env.params.url["value"]

        respon = Scheduler::Utils.find_job_boot(va, env, resources)

        debug_message(env, respon)

        respon
    end

    # enqueue
    #  - echo job_id to caller
    #  -- job_id = "0" ? means failed
    post "/submit_job" do |env|
        job_id, _ = Scheduler::Enqueue.respon(env, resources)

        debug_message(env, job_id)

        job_id
    end

    # file down load server
    get "/job_initrd_tmpfs/:job_id/:job_package" do |env|
        job_id = env.params.url["job_id"]
        job_package = env.params.url["job_package"]
        file_path = ::File.join [resources.@fsdir_root, job_id, job_package]

        debug_message(env, file_path)

        send_file env,  file_path
    end

    # client(runner) report its hostname and mac
    #  - when a runner pull jobs with it's mac infor, scheduler find out what hostname is it
    # /set_host_mac?hostname=$hostname&mac=$mac (mac like ef-01-02-03-04-05)
    # add a <mac> => <hostname>
    # add a <ip> => <hostname>
    # add a <ip:port> => <hostname>
    # !!! how to do : two time calls with diffrent port. JUST use ip?
    # curl -X PUT "http://localhost:3000/set_host_mac?hostname=wfg&mac=00-01-02-03-04-05"
    put "/set_host_mac" do |env|
        if (client_hostname = env.params.query["hostname"]?) && (client_mac = env.params.query["mac"]?)
            sched.set_host_mac(client_mac, client_hostname)

            debug_message(env, "Done")

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
            job_content = {} of String => String
            job_content["id"] = job_id
            resources.@test_params.not_nil!.each do |parameter|
                # update in es (job content)
                if (value = env.params.query[parameter]?)
                    if parameter == "start_time" || parameter == "end_time"
                        value = Time.unix(value.to_i).to_s("%Y-%m-%d %H:%M:%S")
                    end
                    job_content[parameter] = value
                end
            end

            debug_message(env, "Done")

            Scheduler::Monitor.update_job_parameter(job_content, env, resources)
        end

        "Done"
    end

    # client(runner) report job post_run finished
    # /~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40
    #  curl "http://localhost:3000/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40"
    get "/~lkp/cgi-bin/lkp-post-run" do |env|
        # get job_id from request
        job_id = env.params.query["job_id"]?
        if job_id
            debug_message(env, "Done")

            Scheduler::Monitor.update_job_when_finished(job_id, resources)
        end
        "Done"
    end
end
