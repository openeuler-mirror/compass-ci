# SPDX-License-Identifier: MulanPSL-2.0+

require "kemal"
require "yaml"

require "./job"
require "./block_helper"
require "./taskqueue_api"
require "./remote_git_client"
require "../scheduler/constants"
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
    def update_cluster_state(cluster_id, job_id, property, value)
        cluster_state = get_cluster_state(cluster_id)
        if cluster_state[job_id]?
            cluster_state[job_id].merge!({property => value})
            @redis.hash_set("sched/cluster_state", cluster_id, cluster_state.to_json)
        end
    end

    # Return response according to different request states.
    # all request states:
    #     wait_ready | abort | failed | finished | wait_finish |
    #     write_state | roles_ip
    def request_cluster_state(env)
        request_state = env.params.query["state"]
        job_id = env.params.query["job_id"]
        cluster_id = @redis.hash_get("sched/id2cluster", job_id).not_nil!
        cluster_state = ""

        states = {"abort" => "abort",
                  "finished" => "finish",
                  "failed" => "abort",
                  "wait_ready" => "ready",
                  "wait_finish" => "finish"}

        case request_state
        when "abort", "finished", "failed"
            # update node state only
            update_cluster_state(cluster_id, job_id, "state", states[request_state])

        when "wait_ready"
            update_cluster_state(cluster_id, job_id, "state", states[request_state])
            @block_helper.block_until_finished(cluster_id) {
                cluster_state = sync_cluster_state(cluster_id, job_id, states[request_state])
                cluster_state == "ready" || cluster_state == "abort"
            }

            return cluster_state

        when "wait_finish"
            update_cluster_state(cluster_id, job_id, "state", states[request_state])
            while 1
                sleep(10)
                cluster_state = sync_cluster_state(cluster_id, job_id, states[request_state])
                break if (cluster_state == "finish" || cluster_state == "abort")
            end

            return cluster_state

        when "write_state"
            node_roles = env.params.query["node_roles"]
            node_ip = env.params.query["ip"]
            update_cluster_state(cluster_id, job_id, "roles", node_roles)
            update_cluster_state(cluster_id, job_id, "ip", node_ip)

        when "roles_ip"
            role = "server"
            server_ip = get_ip(cluster_id, role)
            return "server=#{server_ip}"
        end

        # show cluster state
        return @redis.hash_get("sched/cluster_state", cluster_id)
    end

    # get the ip of role from cluster_state
    def get_ip(cluster_id, role)
        cluster_state = get_cluster_state(cluster_id)
        cluster_state.each_value do |config|
            if %(#{config["roles"]}) == role
                return config["ip"]
            end
        end
    end

    # node_state: "finish" | "ready"
    def sync_cluster_state(cluster_id, job_id, node_state)
        cluster_state = get_cluster_state(cluster_id)
        cluster_state.each_value do |host_state|
            state = host_state["state"]
            return "abort" if state == "abort"
        end

        cluster_state.each_value do |host_state|
            state = host_state["state"]
            next if "#{state}" == "#{node_state}"
            return "retry"
        end

        # cluster state is node state when all nodes are normal
        return node_state
    end

    # EXAMPLE:
    # cluster_file: "cs-lkp-hsw-ep5"
    # return: Hash(YAML::Any, YAML::Any) | Nil, 0 | <hosts_size>
    #   {"lkp-hsw-ep5" => {"roles" => ["server"], "macs" => ["ec:f4:bb:cb:7b:92"]},
    #    "lkp-hsw-ep2" => {"roles" => ["client"], "macs" => ["ec:f4:bb:cb:54:92"]}}, 2
    def get_cluster_config(cluster_file, lkp_initrd_user, os_arch)
        lkp_src = Jobfile::Operate.prepare_lkp_tests(lkp_initrd_user, os_arch)
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
        job_content["lab"] = LAB unless job_content["lab"]?

        fix_job_content_from_ssh_forward(job_content)

        if job_content["cluster"]?
            cluster_file = job_content["cluster"].to_s
            lkp_initrd_user = job_content["lkp_initrd_user"]? || "latest"
            os_arch = job_content["os_arch"]? || "aarch64"
            cluster_config, hosts_size = get_cluster_config(cluster_file, lkp_initrd_user.to_s, os_arch.to_s)
            if hosts_size >= 2
                return submit_cluster_job(job_content, cluster_config.not_nil!)
            end
        end

        return submit_single_job(job_content)
    end

    # return:
    #   success: [{"job_id" => job_id1, "message => "", "job_state" => "submit"}, ...]
    #   failure: [..., {"job_id" => 0, "message" => err_msg, "job_state" => "submit"}]
    def submit_cluster_job(job_content, cluster_config)
          job_messages = Array(Hash(String, String)).new
          lab = job_content["lab"]

          # collect all job ids
          job_ids = [] of String

          # steps for each host
          cluster_config.each do |host, config|
            tbox_group = host.to_s
            job_id = add_task(tbox_group, lab)

            # return when job_id is '0'
            # 2 Questions:
            #   - how to deal with the jobs added to DB prior to this loop
            #   - may consume job before all jobs done
            return job_messages << {
              "job_id" => "0",
              "message" => "add task queue sched/#{tbox_group} failed",
              "job_state" => "submit"
            } unless job_id

            job_ids << job_id

            # add to job content when multi-test
            job_content["testbox"] = tbox_group
            job_content["tbox_group"] = tbox_group
            job_content["node_roles"] = config["roles"].as_a.join(" ")
            job_content["node_macs"] = config["macs"].as_a.join(" ")

            response = add_job(job_content, job_id)
            message = (response["error"]? ? response["error"]["root_cause"] : "")
            job_messages << {
              "job_id" => job_id,
              "message" => message.to_s,
              "job_state" => "submit"
            }
            return job_messages if response["error"]?
          end

          cluster_id = job_ids[0]

          # collect all host states
          cluster_state = Hash(String, Hash(String, String)).new
          job_ids.each do |job_id|
            cluster_state[job_id] = {"state" => ""}
            # will get cluster id according to job id
            @redis.hash_set("sched/id2cluster", job_id, cluster_id)
          end

          @redis.hash_set("sched/cluster_state", cluster_id, cluster_state.to_json)

          return job_messages
    end

    # return:
    #   success: [{"job_id" => job_id, "message" => "", job_state => "submit"}]
    #   failure: [{"job_id" => "0", "message" => err_msg, job_state => "submit"}]
    def submit_single_job(job_content)
        tbox_group = JobHelper.get_tbox_group(job_content)
        return [{
          "job_id" => "0",
          "message" => "get tbox group failed",
          "job_state" => "submit"
        }] unless tbox_group

        lab = job_content["lab"]
        job_id = add_task(tbox_group, lab)
        return [{
          "job_id" => "0",
          "message" => "add task queue sched/#{tbox_group} failed",
          "job_state" => "submit"
        }] unless job_id

        response = add_job(job_content, job_id)
        message = (response["error"]? ? response["error"]["root_cause"] : "")

        return [{
          "job_id" => job_id,
          "message" => message.to_s,
          "job_state" => "submit"
        }]
    end

    # return job_id
    def add_task(tbox_group, lab)
        task_desc = JSON.parse(%({"domain": "crystal-ci", "lab": "#{lab}"}))
        response = @task_queue.add_task("sched/#{tbox_group}", task_desc)
        JSON.parse(response[1].to_json)["id"].to_s if response[0] == 200
    end

    # add job content to es and return a response
    def add_job(job_content, job_id)
        commit_date = get_commit_date(job_content)
        job_content["commit_date"] = commit_date if commit_date
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
        response = Hash(String, String).new
        response["docker_image"] = "#{job.docker_image}"
        response["lkp"] = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}" +
            JobHelper.service_path("#{SRV_INITRD}/lkp/#{job.lkp_initrd_user}/lkp-#{job.arch}.cgz")
        response["job"] = "http://#{SCHED_HOST}:#{SCHED_PORT}/job_initrd_tmpfs/#{job.id}/job.cgz"

        puts %({"job_id": "#{job.id}", "job_state": "boot"})
        return response.to_json
    end

    private def get_boot_grub(job : Job)
        initrd_lkp_cgz = "lkp-#{job.os_arch}.cgz"

        response = "#!grub\n\n"
        response += "linux (http,#{OS_HTTP_HOST}:#{OS_HTTP_PORT})"
        response += "#{JobHelper.service_path("#{SRV_OS}/#{job.os_dir}/vmlinuz")} user=lkp"
        response += " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job"
        response += " rootovl ip=dhcp ro root=#{job.kernel_append_root}\n"

        response += "initrd (http,#{OS_HTTP_HOST}:#{OS_HTTP_PORT})"
        response += JobHelper.service_path("#{SRV_OS}/#{job.os_dir}/initrd.lkp")
        response += " (http,#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT})"
        response += JobHelper.service_path("#{SRV_INITRD}/lkp/#{job.lkp_initrd_user}/#{initrd_lkp_cgz}")
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
        when "ipxe"
          hostname = @redis.hash_get("sched/mac2host", normalize_mac(api_param))
        when  "grub"
          hostname = @redis.hash_get("sched/mac2host", normalize_mac(api_param))
          if hostname.nil? # auto name new/unknown machine
            hostname = "sut-#{api_param}"
            set_host_mac(api_param, hostname)

            # auto submit a job to collect the host information
            # grub hostname is link with ":", like "00:01:02:03:04:05"
            # remind: if like with "-", last "-05" is treated as host number
            #   then hostname will be "sut-00-01-02-03-04" !!!
            Jobfile::Operate.auto_submit_job(
              "#{ENV["LKP_SRC"]}/jobs/host-info.yaml",
              "testbox: #{hostname}")
          end
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
            job = find_job(hostname)
            if job
                Jobfile::Operate.create_job_cpio(job.dump_to_json_any, Kemal.config.public_folder)
                return get_boot_ipxe(job)
            end
        end

        return ipxe_msg("No next job now")
    end

    private def find_job(testbox : String, count = 1)
        tbox = JobHelper.match_tbox_group(testbox)

        count.times do
            job = prepare_job("sched/#{tbox}", testbox)
            return job if job

            sleep(1) unless count == 1
        end

        tbox_group = tbox.sub(/\-\-\w*/, "")

        count.times do
            job = prepare_job("sched/#{tbox_group}", testbox)
            return job if job

            sleep(1) unless count == 1
        end

        # when find no job at "sched/#{tbox_group}"
        #   try to get from "sched/#{tbox_group}/idle"
        return get_idle_job(tbox_group, testbox)
    end

    private def prepare_job(queue_name, testbox)
        response = @task_queue.consume_task(queue_name)
        job_id = JSON.parse(response[1].to_json)["id"] if response[0] == 200
        job = nil

        if job_id
            job = @es.get_job(job_id.to_s)
            raise "Invalid job (id=#{job_id}) in es" unless job

            job.update({"testbox" => testbox})
            @redis.set_job(job)
        end
        return job
    end

    private def get_idle_job(tbox_group, testbox)
        job = prepare_job("sched/#{tbox_group}/idle", testbox)

        # if there has no idle job, auto submit and get 1
        if job.nil?
            auto_submit_idle_job(tbox_group)
            job = prepare_job("sched/#{tbox_group}/idle", testbox)
        end

        return job
    end

    def auto_submit_idle_job(tbox_group)
        full_path_patterns = "#{ENV["CCI_SRC"]}/allot/idle/#{tbox_group}/*.yaml"
        Jobfile::Operate.auto_submit_job(
            full_path_patterns,
            "testbox: #{tbox_group}/idle") if Dir.glob(full_path_patterns).size > 0
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

        initrd_http_prefix = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
        sched_http_prefix = "http://#{SCHED_HOST}:#{SCHED_PORT}"
        os_http_prefix = "http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}"

        response = "#!ipxe\n\n"
        if job.os_mount == "initramfs"
            response += "initrd #{initrd_http_prefix}" +
                "#{JobHelper.service_path("#{SRV_INITRD}/osimage/#{job.os_dir}/current")}\n"
            response += "initrd #{initrd_http_prefix}" +
                "#{JobHelper.service_path("#{SRV_INITRD}/osimage/#{job.os_dir}/run-ipconfig.cgz")}\n"
        else
            response += "initrd #{os_http_prefix}" +
                "#{JobHelper.service_path("#{SRV_OS}/#{job.os_dir}/initrd.lkp")}\n"
        end
        response += "initrd #{initrd_http_prefix}" +
            "#{JobHelper.service_path("#{SRV_INITRD}/lkp/#{job.lkp_initrd_user}/#{initrd_lkp_cgz}")}\n"
        response += "initrd #{sched_http_prefix}/job_initrd_tmpfs/#{job.id}/job.cgz\n"
        response += initrd_deps
        response += initrd_pkg
        response += "kernel #{os_http_prefix}" +
            "#{JobHelper.service_path("#{SRV_OS}/#{job.os_dir}/vmlinuz")}"
        response += " user=lkp"
        response += " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job rootovl ip=dhcp ro"
        response += " #{job.kernel_append_root}"
        response += add_kernel_console_param(job.os_arch)
        if job.os_mount == "initramfs"
          response += " initrd=#{initrd_lkp_cgz} initrd=job.cgz"
          job.initrd_deps.split().each do |initrd_dep|
            response += " initrd=#{File.basename(initrd_dep)}"
          end
          response += " initrd=#{File.basename(JobHelper.service_path("#{SRV_INITRD}/osimage/#{job.os_dir}/run-ipconfig.cgz"))}\n"
        else
          response += " initrd=#{initrd_lkp_cgz} initrd=job.cgz\n"
        end
        response += "boot\n"

        puts %({"job_id": "#{job.id}", "job_state": "boot"})
        return response
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

        response = @es.set_job_content(job)
        if response["_id"] == nil
            # es update fail, raise exception
            raise "es set job content fail! "
        end

        response = @task_queue.hand_over_task(
            "sched/#{job.tbox_group}", "extract_stats", job_id
        )
        if response[0] != 201
            raise "#{response}"
        end

        @redis.remove_finished_job(job_id)

        puts %({"job_id": "#{job_id}", "job_state": "complete"})
    end

    def fix_job_content_from_ssh_forward(job_content)
        if job_content["SCHED_HOST"] == "127.0.0.1"
           job_content["SCHED_HOST"] = SCHED_HOST
           job_content["LKP_SERVER"] = SCHED_HOST
           job_content["SCHED_PORT"] = SCHED_PORT.to_s
           job_content["LKP_CGI_PORT"] = SCHED_PORT.to_s
        end
    end
end
