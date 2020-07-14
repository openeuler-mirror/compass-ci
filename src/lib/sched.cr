require "kemal"

require "./job"
require "./taskqueue_api"
require "../scheduler/jobfile_operate"
require "../scheduler/redis_client"
require "../scheduler/elasticsearch_client"

class Sched

    property es
    property redis

    def initialize()
        @es = Elasticsearch::Client.new
        @redis = Redis::Client.new
        @task_queue = TaskQueueAPI.new
    end

    def set_host_mac(mac : String, hostname : String)
        @redis.set_hash_queue("sched/mac2host", mac, hostname)
    end

    private def save_job_data(job : Job)
        @es.set_job_content(job)
        @redis.add2queue("sched/jobs_to_run/" + job.tbox_group, job.id)

        return job.id, 0
    end

    def submit_job(env : HTTP::Server::Context)
        body = env.request.body.not_nil!.gets_to_end
        job_content = JSON.parse(body)

        # use redis incr as sched/seqno2jobid
        job_id = @redis.get_new_job_id()
        if job_id == "0"
            return job_id, 1
        end

        job_content["id"] = job_id
        job = Job.new(job_content)

        return save_job_data(job)
    end

    private def ipxe_msg(msg)
        "#!ipxe
        echo ...
        echo #{msg}
        echo ...
        reboot"
    end

    def find_job_boot(mac : String)
        hostname = redis.@client.hget("sched/mac2host", mac)

        job = find_job(hostname, 10) if hostname
        if !job
            return ipxe_msg("No job now")
        end

        Jobfile::Operate.create_job_cpio(job.dump_to_json_any, Kemal.config.public_folder)

        get_job_boot(job)
    end

    private def get_tbox_group_name(testbox : String)
        tbox_group = testbox

        find = testbox.match(/(.*)(\-\d{1,}$)/)
        if find != nil
            tbox_group = find.not_nil![1]
        end

        return tbox_group
    end

    private def find_job(testbox : String, count = 1)
        tbox_group = get_tbox_group_name(testbox)

        count.times do
            response = @task_queue.consume_task("sched/#{tbox_group}")
            job_id = JSON.parse(response[1].to_json)["id"] if response[0] == 200

            if job_id
                job = @es.get_job(job_id.to_s)
                if !job
                    raise "Invalid job (id=#{job_id}) in es"
                end

                @redis.set_job(job)

                return job
            end

            sleep(1)
        end

        return nil
    end

    private def add_kernel_console_param(arch_tmp)
        returned = ""
        if arch_tmp == "x86_64"
           returned = " console=ttyS0,115200 console=tty0"
        end
        return returned
    end

    private def get_pp_initrd(job : Job)
        initrd_deps = ""
        initrd_pkg = ""
        if job.os_mount == "initramfs"
            initrd_deps += job.initrd_deps.split().join(){ |item| "initrd #{item}\n" }
            initrd_pkg += job.initrd_pkg.split().join(){ |item| "initrd #{item}\n" }
        end
        return initrd_deps, initrd_pkg
    end

    private def get_job_boot(job : Job)
        initrd_lkp_cgz = "lkp-#{job.arch}.cgz"

        initrd_deps, initrd_pkg = get_pp_initrd(job)

        respon = "#!ipxe\n\n"
        respon += initrd_deps
        respon += initrd_pkg
        respon += "initrd http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{job.os_dir}/initrd.lkp\n"
        respon += "initrd http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/lkp/#{job.lkp_initrd_user}/#{initrd_lkp_cgz}\n"
        respon += "initrd http://#{SCHED_HOST}:#{SCHED_PORT}/job_initrd_tmpfs/#{job.id}/job.cgz\n"
        respon += "kernel http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{job.os_dir}/vmlinuz user=lkp"
        respon += " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job"
        respon += " root=#{job.kernel_append_root} rootovl ip=dhcp ro"
        respon += add_kernel_console_param(job.arch)
        respon += " initrd=initrd.lkp initrd=#{initrd_lkp_cgz} initrd=job.cgz\n"
        respon += "boot\n"

        return respon
    end

    def update_job_parameter(env : HTTP::Server::Context)
        job_id = env.params.query["job_id"]?
        if !job_id
          return false
        end

        # try to get report value and then update it
        job_content = {} of String => String
        job_content["id"] = job_id

        (%w(start_time end_time loadavg job_state)).each do |parameter|
            value = env.params.query[parameter]?
            if !value
                next
            end
            if parameter == "start_time" || parameter == "end_time"
                value = Time.unix(value.to_i).to_s("%Y-%m-%d %H:%M:%S")
            end

            job_content[parameter] = value
        end

        @redis.update_job(job_content)
    end

    def close_job(job_id : String)
        job = @redis.get_job(job_id)

        respon = @es.set_job_content(job)
        if respon["_id"] == nil
            # es update fail, raise exception
            raise "es set job content fail! "
        end

        @redis.remove_finished_job(job_id)
    end
end
