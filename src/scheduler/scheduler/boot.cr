require  "./resources"
require "./../../lib/job.cr"
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
        def self.add_kernel_console_param(arch_tmp)
            returned = ""
            if arch_tmp == "x86_64"
                returned = " console=ttyS0,115200 console=tty0"
            end
            return returned
        end

        private def self.get_pp_initrd(job : Job)
            initrd_deps = ""
            initrd_pkg = ""
            if job.os_mount == "initramfs"
              initrd_deps += job.initrd_deps.split().join(){ |item| "initrd #{item}\n" }
              initrd_pkg += job.initrd_pkg.split().join(){ |item| "initrd #{item}\n" }
            end
            return initrd_deps, initrd_pkg
        end


        def self.respon(job : Job, env, resources : Scheduler::Resources)
            initrd_lkp_cgz = "lkp-#{job.arch}.cgz"

            initrd_deps, initrd_pkg = self.get_pp_initrd(job)

            respon = "#!ipxe\n\n"
            respon += initrd_deps
            respon += initrd_pkg
            respon += "initrd http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{job.os_dir}/initrd.lkp\n"
            respon += "initrd http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/lkp/#{job.lkp_initrd_user}/#{initrd_lkp_cgz}\n"
            respon += "initrd http://#{SCHED_HOST}:#{SCHED_PORT}/job_initrd_tmpfs/#{job.id}/job.cgz\n"
            respon += "kernel http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{job.os_dir}/vmlinuz user=lkp"
            respon += " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job"
            respon += " root=#{job.kernel_append_root} rootovl ip=dhcp ro"
            respon += self.add_kernel_console_param(job.arch)
            respon += " initrd=initrd.lkp initrd=#{initrd_lkp_cgz} initrd=job.cgz\n"
            respon += "boot\n"
            return respon
        end
    end
end
