require  "./resources"

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
        def self.respon(job_id : String, env, resources : Scheduler::Resources) 

            respon = "#!ipxe\n\n"

            # the localhost should configure to <os and lkp> hostname
            server = "172.168.131.113"
            scheduler = "172.17.0.1"

            case job_id
            when "0"
                respon = respon + "echo ...\necho No job now\necho ...\nreboot\n"
            else
                # job_id = "29" # temp set to fix job (corresponding to job config)
                respon = respon + "initrd http://#{server}:8000/os/debian/initrd.lkp\n"
                respon = respon + "initrd http://#{server}:8800/initrd/lkp/latest/lkp-aarch64.cgz\n"
                respon = respon + "initrd http://#{scheduler}:3000/job_initrd_tmpfs/#{job_id}/job.cgz\n"
                respon = respon + "kernel http://#{server}:8000/os/debian/vmlinuz user=lkp"
                respon = respon + " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job"
                respon = respon + " root=#{server}:/os/debian rootovl ip=enp0s1:dhcp ro"
                respon = respon + " initrd=initrd.lkp initrd=lkp-aarch64.cgz initrd=job.cgz\n"
                respon = respon + "boot\n"
            end
            return respon
        end
    end
end