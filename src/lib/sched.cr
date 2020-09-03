# SPDX-License-Identifier: MulanPSL-2.0+

require "kemal"
require "yaml"

require "./job"
require "./block_helper"
require "./taskqueue_api"
require "./remote_git_client"
require "../scheduler/jobfile_operate"
require "../scheduler/redis_client"
require "../scheduler/elasticsearch_client"

class Sched

    property es
    property redis
    property block_helper

    def initialize()
        @es = Elasticsearch::Client.new
        @redis = Redis::Client.new
        @task_queue = TaskQueueAPI.new
        @block_helper = BlockHelper.new
        @rgc = RemoteGitClient.new
    end

    def normalize_mac(mac : String)
        mac.gsub(":", "-")
    end

    def set_host_mac(mac : String, hostname : String)
        @redis.hash_set("sched/mac2host", normalize_mac(mac), hostname)
    end

    def del_host_mac(mac : String)
        @redis.hash_del("sched/mac2host", normalize_mac(mac))
    end

    # return:
    #     Hash(String, Hash(String, String))
    def get_cluster_state(cluster_id)
        cluster_state = @redis.hash_get("sched/cluster_state", cluster_id)
        if cluster_state
            cluster_state = Hash(String, Hash(String, String)).from_json(cluster_state)
        else
            cluster_state = Hash(String, Hash(String, String)).new
        end
        return cluster_state
    end

    # get -> modify -> set
    def update_cluster_state(cluster_id, job_id, state)
        cluster_state = get_cluster_state(cluster_id)
        cluster_state.merge!({job_id => {"state" => state}})
        @redis.hash_set("sched/cluster_state", cluster_id, cluster_state.to_json)
    end

    # Return response according to different request states.
    #
    # all request states:
    #     wait_ready | abort | failed | finished | wait_finish |
    #     write_state | roles_ip
    # NOTE: have't implemented until now:
    #     write_state | roles_ip
    def request_cluster_state(env)
        request_state = env.params.query["state"]
        job_id = env.params.query["job_id"]
        cluster_id = @redis.hash_get("sched/id2cluster", job_id)

        states = {"abort" => "abort",
                  "finished" => "finish",
                  "failed" => "abort",
                  "wait_ready" => "ready",
                  "wait_finish" => "finish"}

        case request_state
        when "abort", "finished", "failed"
            # update node state only
            update_cluster_state(cluster_id, job_id, states[request_state])

        when "wait_ready", "wait_finish"
            # return cluster state: ready | retry | finish | abort
            return sync_cluster_state(cluster_id, job_id, states[request_state])
        end

        # show cluster state
        return @redis.hash_get("sched/cluster_state", cluster_id)
    end

    # node_state: "finish" | "ready"
    def sync_cluster_state(cluster_id, job_id, node_state)
        update_cluster_state(cluster_id, job_id, node_state)
        sleep(10)

        cluster_state = get_cluster_state(cluster_id)
        cluster_state.each_value do |host_state|
            state = host_state["state"]
            return "abort" if state == "abort"
            flag = need_retry(node_state, state)
            return "retry" if flag
        end

        # cluster state is node state when all nodes are normal
        return node_state
    end

    # | node_state    | "ready"      | "finish"      | ↓
    # | state         | ""(empty)    | "ready"       | ↓
    # | retry?        |    true      |    true       | ↓
    def need_retry(node_state, state)
        flag = false

        case node_state
        when "ready"
            flag = true if state.empty?
        when "finish"
            flag = true if state == "ready"
        end

        return flag
    end

    # EXAMPLE:
    # cluster_file: "cs-lkp-hsw-ep5"
    # return: Hash(YAML::Any, YAML::Any) | Nil, 0 | <hosts_size>
    #   {"lkp-hsw-ep5" => {"roles" => ["server"], "macs" => ["ec:f4:bb:cb:7b:92"]},
    #    "lkp-hsw-ep2" => {"roles" => ["client"], "macs" => ["ec:f4:bb:cb:54:92"]}}, 2
    def get_cluster_config(cluster_file)
        lkp_src = ENV["LKP_SRC"] || "/c/lkp-tests"
        cluster_file_path = Path.new(lkp_src, "cluster", cluster_file)

        if File.file?(cluster_file_path)
          cluster_config = YAML.parse(File.read(cluster_file_path)).as_h
          hosts_size = cluster_config.values.size
          return cluster_config, hosts_size
        end

        return nil, 0
    end

    def get_commit_date(job_content : JSON::Any)
      if job_content["upstream_repo"]? && job_content["upstream_commit"]?
        data = JSON.parse(%({"git_repo": "#{job_content["upstream_repo"]}.git",
                          "git_command": ["git-log", "--pretty=format:%cd", "--date=unix",
                          "#{job_content["upstream_commit"]}", "-1"]}))
        response = @rgc.git_command(data)
        return response.body if response.status_code == 200
      end

      return nil
    end

    def submit_job(env : HTTP::Server::Context)
        body = env.request.body.not_nil!.gets_to_end
        job_content = JSON.parse(body)

        if job_content["cluster"]?
            cluster_file = job_content["cluster"].to_s
            cluster_config, hosts_size = get_cluster_config(cluster_file)
            if hosts_size >= 2
                return submit_cluster_job(job_content, cluster_config.not_nil!)
            end
        end

        return submit_single_job(job_content)
    end

    # for multi-device.
    # cluster_config: Hash(YAML::Any, YAML::Any)
    #    {"lkp-hsw-ep5" => {"roles" => ["server"], "macs" => ["ec:f4:bb:cb:7b:92"]},
    #     "lkp-hsw-ep2" => {"roles" => ["client"], "macs" => ["ec:f4:bb:cb:54:92"]}},
    # return:
    #   job_ids : success
    #       "0" : failure
    def submit_cluster_job(job_content, cluster_config)
          # collect all job ids
          job_ids = [] of String

          # steps for each host
          cluster_config.each do |host, config|
            tbox_group = host.to_s
            job_id = add_task(tbox_group)

            # return when job_id is '0'
            # 2 Questions:
            #   - how to deal with the jobs added to DB prior to this loop
            #   - may consume job before all jobs done
            job_id == "0" && (return "0")
            job_ids << job_id

            # add to job content when multi-test
            job_content["testbox"] = tbox_group
            job_content["tbox_group"] = tbox_group
            job_content["node_roles"] = config["roles"].as_a.join(" ")
            job_content["node_macs"] = config["macs"].as_a.join(" ")
            add_job(job_content, job_id)
          end

          cluster_id = job_ids[0]
          # collect all host states
          cluster_state = Hash(String, Hash(String, String)).new

          job_ids.each do |job_id|
            # only collect host state until now
            cluster_state[job_id] = {"state" => ""}
            # will get cluster id according to job id
            @redis.hash_set("sched/id2cluster", job_id, cluster_id)
          end

          @redis.hash_set("sched/cluster_state", cluster_id, cluster_state.to_json)

          job_ids.to_s
    end

    # for one-device
    def submit_single_job(job_content)
        tbox_group = JobHelper.get_tbox_group(job_content)
        job_id = add_task(tbox_group)
        job_id == "0" && (return "0")
        add_job(job_content, job_id)
        return job_id
    end

    # add a task to task-queue and return a job_id
    # return:
    #     job_id : success
    #        "0" : failure
    def add_task(tbox_group)
        task_desc = JSON.parse(%({"domain": "crystal-ci"}))
        response = @task_queue.add_task("sched/#{tbox_group}", task_desc)
        job_id = JSON.parse(response[1].to_json)["id"].to_s if response[0] == 200
        job_id || "0"
    end

    # add job content to es
    def add_job(job_content, job_id)
        job_content["id"] = job_id
        job = Job.new(job_content)
        @es.set_job_content(job)
    end

    private def ipxe_msg(msg)
        "#!ipxe
        echo ...
        echo #{msg}
        echo ...
        reboot"
    end

    private def grub_msg(msg)
        "#!grub
        echo ...
        echo #{msg}
        echo ...
        reboot"
    end

    private def get_boot_container(job : Job)
        respon = Hash(String, String).new
        respon["docker_image"] = "#{job.docker_image}"
        respon["lkp"] = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/lkp/#{job.lkp_initrd_user}/lkp-#{job.arch}.cgz"
        respon["job"] = "http://#{SCHED_HOST}:#{SCHED_PORT}/job_initrd_tmpfs/#{job.id}/job.cgz"

        puts %({"job_id": "#{job.id}", "job_state": "boot"})
        return respon.to_json
    end

    private def get_boot_grub(job : Job)
        initrd_lkp_cgz = "lkp-#{job.os_arch}.cgz"

        response = "#!grub\n\n"
        response += "linux (http,#{OS_HTTP_HOST}:#{OS_HTTP_PORT})/os/"
        response += "#{job.os_dir}/vmlinuz user=lkp"
        response += " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job"
        response += " rootovl ip=dhcp ro root=#{job.kernel_append_root}\n"

        response += "initrd (http,#{OS_HTTP_HOST}:#{OS_HTTP_PORT})/os/"
        response += "#{job.os_dir}/initrd.lkp"
        response += " (http,#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT})/initrd/"
        response += "lkp/#{job.lkp_initrd_user}/#{initrd_lkp_cgz}"
        response += " (http,#{SCHED_HOST}:#{SCHED_PORT})/job_initrd_tmpfs/"
        response += "#{job.id}/job.cgz\n"

        response += "boot\n"

        puts %({"job_id": "#{job.id}", "job_state": "boot"})
        return response
    end

    def boot_content(job : Job | Nil, boot_type : String)
        case boot_type
        when "ipxe"
          return job ? get_boot_ipxe(job) : ipxe_msg("No job now")
        when "grub"
          return job ? get_boot_grub(job) : grub_msg("No job now")
        when "container"
          return job ? get_boot_container(job) : Hash(String, String).new.to_json
        else
          raise "Not defined boot type #{boot_type}"
        end
    end

    def find_job_boot(env : HTTP::Server::Context)
        api_param = env.params.url["value"]

        case env.params.url["boot_type"]
        when "ipxe", "grub"
          hostname = @redis.hash_get("sched/mac2host", normalize_mac(api_param))
        when "container"
          hostname = api_param
        end

        job = find_job(hostname) if hostname
        Jobfile::Operate.create_job_cpio(job.dump_to_json_any, Kemal.config.public_folder) if job

        return boot_content(job, env.params.url["boot_type"])
    end

    def find_next_job_boot(env)
        hostname = env.params.query["hostname"]?
        mac = env.params.query["mac"]?
        if !hostname && mac
          hostname = @redis.hash_get("sched/mac2host", normalize_mac(mac))
        end

        if hostname
            job = find_job(hostname, 10)
            if job
                Jobfile::Operate.create_job_cpio(job.dump_to_json_any, Kemal.config.public_folder)
                return get_boot_ipxe(job)
            end
        end

        return ipxe_msg("No next job now")
    end

    private def find_job(testbox : String, count = 1)
        tbox_group = JobHelper.match_tbox_group(testbox)

        count.times do
            response = @task_queue.consume_task("sched/#{tbox_group}")
            job_id = JSON.parse(response[1].to_json)["id"] if response[0] == 200

            if job_id
                job = @es.get_job(job_id.to_s)
                if !job
                    raise "Invalid job (id=#{job_id}) in es"
                end

                job.update({"testbox" => testbox})
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

    private def get_boot_ipxe(job : Job)
        initrd_lkp_cgz = "lkp-#{job.os_arch}.cgz"

        initrd_deps, initrd_pkg = get_pp_initrd(job)

        respon = "#!ipxe\n\n"
        respon += initrd_deps
        respon += initrd_pkg
        if job.os_mount == "initramfs"
            respon += "initrd http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/osimage/#{job.os_dir}/current\n"
            respon += "initrd http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/osimage/#{job.os_dir}/run-ipconfig.cgz\n"
        else
            respon += "initrd http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{job.os_dir}/initrd.lkp\n"
        end
        respon += "initrd http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/lkp/#{job.lkp_initrd_user}/#{initrd_lkp_cgz}\n"
        respon += "initrd http://#{SCHED_HOST}:#{SCHED_PORT}/job_initrd_tmpfs/#{job.id}/job.cgz\n"
        respon += "kernel http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{job.os_dir}/vmlinuz user=lkp"
        respon += " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job rootovl ip=dhcp ro"
        respon += " root=#{job.kernel_append_root}"
        respon += add_kernel_console_param(job.os_arch)
        if job.os_mount == "initramfs"
          respon += " initrd=#{initrd_lkp_cgz} initrd=job.cgz initrd=run-ipconfig.cgz\n"
        else
          respon += " initrd=#{initrd_lkp_cgz} initrd=job.cgz\n"
        end
        respon += "boot\n"

        puts %({"job_id": "#{job.id}", "job_state": "boot"})
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
            if !value || value == ""
                next
            end
            if parameter == "start_time" || parameter == "end_time"
                value = Time.unix(value.to_i).to_s("%Y-%m-%d %H:%M:%S")
            end

            job_content[parameter] = value
        end

        @redis.update_job(job_content)

        # json log
        log = job_content.dup
        log["job_id"] = log.delete("id").not_nil!
        puts log.to_json
    end

    def update_tbox_wtmp(env : HTTP::Server::Context)
        testbox = ""
        hash = Hash(String, String).new

        timestamp = Time.local.to_unix
        time = Time.unix(timestamp).to_s("%Y-%m-%d %H:%M:%S")
        hash["time"] = time

        %w(mac ip job_id tbox_name tbox_state).each do |parameter|
            if (value = env.params.query[parameter]?)
                case parameter
                when "tbox_name"
                    testbox = value
                when "tbox_state"
                    hash["state"] = value
                when "mac"
                    hash["mac"] = normalize_mac(value)
                else
                    hash[parameter] = value
                end
            end
        end

        @redis.update_wtmp(testbox, hash)

        # json log
        hash["testbox"] = testbox
        puts hash.to_json
    end

    def close_job(job_id : String)
        job = @redis.get_job(job_id)

        respon = @es.set_job_content(job)
        if respon["_id"] == nil
            # es update fail, raise exception
            raise "es set job content fail! "
        end

        respon = @task_queue.hand_over_task(
            "sched/#{job.tbox_group}", "extract_stats", job_id
        )
        if respon[0] != 201
            raise "#{respon}"
        end

        @redis.remove_finished_job(job_id)

        puts %({"job_id": "#{job_id}", "job_state": "complete"})
    end
end
