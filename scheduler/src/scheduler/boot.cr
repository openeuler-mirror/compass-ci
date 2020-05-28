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
	def self.ipxe_msg(msg)
	    "#!ipxe\n\n
	    echo ...\n
	    echo #{msg}\n
	    echo ...\n
	    reboot"
	end

        def self.respon(job_content : JSON::Any, env, resources : Scheduler::Resources) 
            respon = "#!ipxe\n\n"

            # the localhost should configure to <os and lkp> hostname
            server = "172.168.131.113"
            scheduler = "172.17.0.1"

            # job_id = "29" # temp set to fix job (corresponding to job config)
            respon = respon + "initrd http://#{server}:8000/os/debian/aarch64/sid/initrd.lkp\n"
            respon = respon + "initrd http://#{server}:8800/initrd/lkp/latest/lkp-aarch64.cgz\n"
            respon = respon + "initrd http://#{scheduler}:3000/job_initrd_tmpfs/#{job_content["id"]}/job.cgz\n"
            respon = respon + "kernel http://#{server}:8000/os/debian/aarch64/sid/vmlinuz user=lkp"
            respon = respon + " job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job"
            respon = respon + " root=#{server}:/os/debian/aarch64/sid rootovl ip=enp0s1:dhcp ro"
            respon = respon + " initrd=initrd.lkp initrd=lkp-aarch64.cgz initrd=job.cgz\n"
            respon = respon + "boot\n"
            return respon
        end
    end
end
