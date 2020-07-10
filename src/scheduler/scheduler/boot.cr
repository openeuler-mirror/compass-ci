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

        def self.get_os_dir(job_content : JSON::Any)
            if job_content["os"]?
                job_content["os"].to_s + "/" + job_content["os_arch"].to_s + "/" + job_content["os_version"].to_s
            else
                "debian/aarch64/sid"
            end
        end

        def self.get_lkp_initrd_user(job_content : JSON::Any)
            if job_content["lkp_initrd_user"]?
                job_content["lkp_initrd_user"].to_s
            else
                "latest"
            end
        end

        def self.add_kernel_console_param(arch_tmp)
            returned = ""
            if arch_tmp == "x86_64"
                returned = " console=ttyS0,115200 console=tty0"
            end
            return returned
        end

        def self.respon(job_content : JSON::Any, env, resources : Scheduler::Resources)
            os_dir = self.get_os_dir(job_content)
            lkp_initrd_user = self.get_lkp_initrd_user(job_content)

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

            # root value need to depend on os_mount field
            root_value = ""
            if job_content["os_mount"]?
                case job_content["os_mount"].to_s
                when "initramfs"
                    respon += initrd_deps_arr.join(){|item| "initrd #{item}\n"}
                    respon += initrd_pkg_arr.join(){|item| "initrd #{item}\n"}
                    root_value = "/dev/ram0"
                when "cifs"
                    root_value = "cifs://#{OS_HTTP_HOST}/os/#{os_dir},guest,ro,hard,vers=1.0,noacl,nouser_xattr"
                when "nfs"
                    root_value = "#{OS_HTTP_HOST}:/os/#{os_dir}"
                end
            else
                root_value = "#{OS_HTTP_HOST}:/os/#{os_dir}"
            end

            job_hash_merge = job_hash.merge({"initrd_deps" => initrd_deps_arr.join(" "), "initrd_pkg" => initrd_pkg_arr.join(" ")})
            job_content = JSON.parse(job_hash_merge.to_json)

            initrd_lkp_cgz = "lkp-#{job_content["arch"]}.cgz"
            respon += "initrd http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{os_dir}/initrd.lkp\n"
            respon += "initrd http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/lkp/#{lkp_initrd_user}/#{initrd_lkp_cgz}\n"
            respon += "initrd http://#{SCHED_HOST}:#{SCHED_PORT}/job_initrd_tmpfs/#{job_content["id"]}/job.cgz\n"
            respon += "kernel http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{os_dir}/vmlinuz user=lkp"
            respon += " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job"
            respon += " root=#{root_value} rootovl ip=dhcp ro"
            respon += self.add_kernel_console_param(job_content["arch"])
            respon += " initrd=initrd.lkp initrd=#{initrd_lkp_cgz} initrd=job.cgz\n"
            respon += "boot\n"
            return respon, job_content
        end
    end
end
