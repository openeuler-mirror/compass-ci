require  "./resources"
require "./../constants.cr"
# respon ipxe command to qemu-runner
# - No job now
#    #!ipxe
#    echo No job now
#    reboot
#
# - job boot file
#    #!ipxe
#     initrd ...
#     kernel ...
#     boot ...
#

module Scheduler
    module Boot
        def self.ipxe_msg(msg)
            "#!ipxe
            echo ...
            echo #{msg}
            echo ...
            reboot"
        end

        def self.respon(job_content : JSON::Any, env, resources : Scheduler::Resources)
            if job_content["os"]?
                os_dir = job_content["os"].to_s + "/" + job_content["os_arch"].to_s + "/" + job_content["os_version"].to_s
            else
                os_dir = "debian/aarch64/sid"
            end

            if job_content["lkp_initrd_user"]?
                lkp_initrd_user = job_content["lkp_initrd_user"].to_s
            else
                lkp_initrd_user = "latest"
            end

            # the localhost should configure to <os and lkp> hostname
            respon = "#!ipxe\n\n"
            job_hash = job_content.as_h
            initrd_deps_arr = Array(String).new
            initrd_pkg_arr = Array(String).new
            if job_content["pp"]?
              program_params = job_content["pp"].as_h
              program_params.keys.each do |program|
                  if File.exists?("#{ENV["LKP_SRC"]}/distro/depends/#{program}") &&
                     File.exists?("/srv/initrd/deps/#{os_dir}/#{program}.cgz")
                      initrd_deps_arr << "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/deps/#{os_dir}/#{program}.cgz"
                  end
                  if File.exists?("#{ENV["LKP_SRC"]}/pkg/#{program}") &&
                     File.exists?("/srv/initrd/pkg/#{os_dir}/#{program}.cgz")
                      initrd_pkg_arr << "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/pkg/#{os_dir}/#{program}.cgz"
                  end
              end
            end
            if job_content["os_mount"]? && job_content["os_mount"].to_s == "initramfs"
                respon += initrd_deps_arr.join(){|item| "initrd #{item}\n"}
                respon += initrd_pkg_arr.join(){|item| "initrd #{item}\n"}
            end
            job_hash_merge = job_hash.merge({"initrd_deps" => initrd_deps_arr.join(" "), "initrd_pkg" => initrd_pkg_arr.join(" ")})
            job_content = JSON.parse(job_hash_merge.to_json)

            respon += "initrd http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{os_dir}/initrd.lkp\n"
            respon += "initrd http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/lkp/#{lkp_initrd_user}/lkp-aarch64.cgz\n"
            respon += "initrd http://#{SCHED_HOST}:#{SCHED_PORT}/job_initrd_tmpfs/#{job_content["id"]}/job.cgz\n"
            respon += "kernel http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{os_dir}/vmlinuz user=lkp"
            respon += " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job"
            respon += " root=#{OS_HTTP_HOST}:/os/#{os_dir} rootovl ip=enp0s1:dhcp ro"
            respon += " initrd=initrd.lkp initrd=lkp-aarch64.cgz initrd=job.cgz\n"
            respon += "boot\n"
            return respon, job_content
        end
    end
end
