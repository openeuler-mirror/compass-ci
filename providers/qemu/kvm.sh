#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - nr_cpu
# - memory

: ${nr_cpu:=1}
: ${memory:=1G}
: ${log_dir:=/srv/cci/serial/logs}

source ${CCI_SRC}/lib/log.sh
source ${LKP_SRC}/lib/upload.sh

oops_patterns=(
	-e 'Kernel panic - not syncing:'
	-e 'NULL pointer dereference'

	# /c/linux/arch/arm64/mm/fault.c
	-e 'Unable to handle kernel '

	# /c/linux/arch/x86/mm/fault.c
	-e 'BUG: unable to handle page fault'
)

check_logfile()
{
	log_file=${log_dir}/${hostname}
	[ -f "$log_file" ] || {
		touch $log_file
		# fluentd refresh time is 1s
		# let fluentd to monitor this file first
		sleep 2
	}
}

mem_available()
{
	# refer to ~/lkp-tests/lkp-exec/qemu
	# MemAvailable = MemFree + (Active_file/2) + Inactive_file
	local memory_available mem_free active_file inactive_file

	mem_free=$(cat /proc/meminfo | awk '/MemFree/ {print $2}')
	active_file=$(cat /proc/meminfo | awk '/Active\(file\)/ {print $2}')
	inactive_file=$(cat /proc/meminfo | awk '/Inactive\(file\)/ {print $2}')

	(( memory_available = mem_free + (active_file/2) + inactive_file ))

	## kB -> GB
	echo $((memory_available >> 20))
}

low_mem_wait()
{
	local vm_required_memory
	vm_required_memory=$(($(echo $memory | tr -d G) * 3 / 2))
	
	# when available memory is less than the vm required, program will wait
	while [ $(mem_available) -lt ${vm_required_memory} ]
	do
		echo "available memory is not enough: $(mem_available) < ${vm_required_memory}, wait 30s"
		sleep 30
	done
}

write_logfile()
{
	ipxe_script=ipxe_script
    # check if need safe-stop:
	# - stop multi-qemu systemd
	# - stop all multi-qemu process
	#   - curling vm: stop after curl timeout <== following code used for this step
	#   - running vm: stop after vm run finished
	# - kill sleep $runtime process
	# - then lkp will reboot hw.
    if [ -f "/tmp/$HOSTNAME/safe-stop" ]; then
        log_info "safe stop: $hostname" | tee -a $log_file
        exit 0
    fi

	# check if need restart:
	# - upgrade code
	# - stop all multi-qemu process
	#   - curling vm: stop after curl timeout <== following code used for this step
	#   - running vm: stop after vm run finished
	# - start multi-qemu process by systemd
	#
	# what's UUID:
	# - UUID is generate at the beginning of ${CCI_SRC}/providers/multi-qemu.
	# - then, if multi-qemu need restart, `/tmp/$HOSTNAME/restart/$UUID` will be generated,
	# - so curl will exit.
    if [ -n "$UUID" ] && [ -f "/tmp/$HOSTNAME/restart/$UUID" ]; then
        log_info "restart vm with uuid. vm: $hostname. uuid: $UUID" | tee -a $log_file
        exit 0
    fi
    
	while true
	do
		log_info "start request job: $hostname" | tee -a $log_file

		# empty file
		# prevent the contents of the last file from being affected
		echo -n '' > $ipxe_script

		url=ws://${SCHED_HOST:-172.17.0.1}:${SCHED_PORT:-3000}/ws/boot.ipxe/mac/${mac}
		ipxe_script_path="$(pwd)/${ipxe_script}"
		command -v ruby &&
			ruby -r "${CCI_SRC}/providers/lib/common.rb" -e "ws_boot '$url','$hostname','$index','$ipxe_script_path'"

		cat $ipxe_script | grep "No job now" && {
			log_info "no job now: $hostname" | tee -a $log_file
			continue
		}

		log_info "got job: $hostname" | tee -a $log_file
		break
	done
}

parse_ipxe_script()
{
	append=
	initrds=
	while read a b c
	do
		case "$a" in
			'#')
				;;
			initrd)
				file=$(basename "$b")
				[ $file == "job.cgz" ] && {
					job_id=$(basename $(dirname "$b"))
				}
				wget --timestamping -nv -a ${log_file} $b
				initrds+="$file "
				;;
			kernel)
				kernel=$(basename "$b")
				wget --timestamping -nv -a ${log_file} $b
				append=$(echo "$c" | sed -r "s/ initrd=[^ ]+//g")
				;;
			*)
				;;
		esac
	done < $ipxe_script

	# why add job_id:
	# - one vm executes different job in different time, but the runtime workdir for one vm won't change.
	# - so job id of vm in different time is important obviously.
	# - so we record the job id, and for the possible usage. such as business monitor, etc.
	echo $job_id > job_id
}

check_kernel()
{
	[ -n "$kernel" ] || {
		log_info "Can not find job for current hostname: $hostname." | tee -a $log_file
		exit 0
	}

	[ -s "$kernel" ] || {
		log_error "Can not find kernel file or kernel file is empty: $kernel." | tee -a $log_file
		exit 1
	}
}

check_qemu()
{
	# debian has both qemu-system-x86_64 and qemu-system-riscv64 command
	[[ $kernel =~ 'riscv64' ]] && {
		command -v qemu-system-riscv64 > /dev/null && qemu=qemu-system-riscv64
	}
}

check_initrds()
{
	if [ -n "$initrds" ]; then
		cat $initrds > concatenated-initrd
	else
		log_error "The current initrds is null." | tee -a $log_file
		exit 1
	fi
}

set_bios()
{
       bios=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd
       # when arch='x86_64', use the following file: 
       [ -f "$bios" ] || bios=/usr/share/ovmf/OVMF.fd
}

set_helper()
{
       helper=/usr/libexec/qemu-bridge-helper
       [ -f "$helper" ] || helper=/usr/lib/qemu/qemu-bridge-helper
}

is_full()
{
	local used_size=$1
	local disk_size=$2

	if [ ${used_size: -1} != "G" ] && [ ${used_size: -1} != "g" ]; then
		return -1
	fi

	local num_used=$(echo $used_size | tr -dc "[0-9.]" | cut -d '.' -f1)
	local num_disk=$(echo $disk_size | tr -dc "[0-9.]")

	if [ $num_used -lt $num_disk ]; then
		return -1
	fi

	return 0
}

over_time()
{
	local file_path=$1
	local mtime=$(stat -c %Y $file_path)
	local now_time=$(date +%s)
	local ten_day_sec=864000

	if [ $((now_time - mtime)) -gt "$ten_day_sec" ]; then
		return 0
	fi

	return -1
}

prepare_disk()
{
	# - disk size:	required	default: 512G.
	# - need_clean: optional	true|false, default: false

	local disk_size=$1
	local need_clean=${2:-"false"}

	qcow2_file="${qemu_mount_point}/${hostname}-${disk##*/}.qcow2"

	if [ -f "$qcow2_file" ]; then
		local used_size=$(du -h "${qcow2_file}" | awk -F ' ' '{print $1}')

		if over_time "$qcow2_file" && is_full "$used_size" "$disk_size"; then
			need_clean=true
		else
			need_clean=false
		fi
	fi

	if [ "$need_clean" == "true" ]; then
		qemu-img create -q -f qcow2 "${qcow2_file}" $disk_size
	else
		[ -f "$qcow2_file" ] || qemu-img create -q -f qcow2 "${qcow2_file}" $disk_size
	fi
}

add_disk()
{
	# VM testbox has disk spec?
	[ -n "$hdd_partitions" ] || [ -n "$rootfs_disk" ] || return 0

	local mnt
	for mnt in $mount_points; do
		[[ "$mnt" =~ "multi-qemu" ]] && qemu_mount_point="$mnt" && break
	done
	[ -n "$qemu_mount_point" ] || qemu_mount_point=$(pwd)

	local disk
	disk_encode=('/vdb' '/vdc' '/vdd' '/vde' '/vdf' '/vdg' '/vdh' '/vdi' '/vdj' '/vdk' '/vdl' '/vdm' '/vdn' '/vdo' '/vdp' '/vdq' '/vdr' '/vds' '/vdt' '/vdu' '/vdv' '/vdw' '/vdx' '/vdy')

	# create rootfs disk
	create_disk 0 "/dev/vda"

	local index=1
	if([ -n "$nr_hdd_partitions" ]); then
		for((i=0;i<$nr_hdd_partitions;i++)); do
			disk=${disk_encode[$index-1]}
			create_disk $index $disk
			((index++))
		done
	else
		for disk in ${hdd_partitions[@]}
		do
			create_disk $index $disk
			((index++))
		done
	fi

	if [ -n "$nr_ssd_partitions" ]; then
		for((i=0;i<$nr_ssd_partitions;i++)); do
			disk=${disk_encode[$index-1]}
			create_disk $index $disk
			((index++))
		done
	fi
}

create_disk()
{
	local index=$1
	local disk=$2
	prepare_disk "128G" "true"

	# about if=virtio:
	# - let the qemu recognize disk as virtio_blk, then the device name will be /dev/vd[a-z].
	# - to avoid the given device name is not the same as the real device name.
	local drive="file=${qcow2_file},media=disk,format=qcow2,index=${index},if=virtio"
	kvm+=(-drive ${drive})
}
set_mac()
{
	job_id=$(awk -F'/' '/job_initrd_tmpfs/{print $(NF-1)}' $ipxe_script)
	nr_nic=$(awk -F'=' '/# nr_nic=/{print NF}' $ipxe_script)

	if [ $(command -v es-find) ]; then
		nr_nic=$(es-find id=$job_id | awk '/nr_nic/{print $2}' | tr -d ,)
	else
		echo "command not found: es-find. set nr_nic=1"
		sleep 1
	fi

	mac_arr[1]=$mac
	nr_nic=${nr_nic:-1}

	[ "$nr_nic" -ge "2" ] || return
	for i in $(seq 2 $nr_nic)
	do
	        mac=$(echo $hostname$i | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/0a-\1-\2-\3-\4-\5/')
	        mac_arr[$i]=$mac
	done
}

set_nic()
{
        for i in $(seq 1 $nr_nic)
        do
		br="br$((i-1))"
		[ -f "/sys/class/net/${br}/address" ] || continue
		nic[$i]="-nic tap,model=virtio-net-pci,helper=${helper},br=${br},mac=${mac_arr[$i]}"

        done
}

set_device()
{
	device="virtio-net-device,netdev=net0,mac=${mac}"
}

set_netdev()
{
	netdev="bridge,br=br0,id=net0,helper=${helper}"
}

set_qemu()
{
	qemus=(
		qemu-system-$(arch)
		qemu-kvm
	)

	for qemu_candidate in "${qemus[@]}"
	do
		command -v "$qemu_candidate" > /dev/null && {
			qemu="$qemu_candidate"
			break
		}
	done

	check_qemu
}

print_message()
{
	log_info SCHED_PORT: $SCHED_PORT | tee -a $log_file
	log_info kernel: $kernel | tee -a $log_file
	log_info initrds: $initrds | tee -a $log_file
	log_info append: $append | tee -a $log_file
	[ "$DEBUG" == "true" ] || log_info less $log_file

	sleep 5
}

public_option()
{
	kvm=(
		$qemu_prefix
		$qemu
		-name guest=$hostname,process=$job_id
		-kernel $kernel
		-initrd concatenated-initrd
		-smp $nr_cpu
		-m $memory
		-rtc base=localtime
		-k en-us
		-no-reboot
		-nographic
		-monitor null
		-pidfile qemu.pid
	)

	[ -n "$cpu_model" ] && kvm+="-cpu $cpu_model"
}

individual_option()
{
	case "$qemu" in
		qemu-system-aarch64)
			arch_option=(
					-machine virt-4.0,accel=kvm,gic-version=3
					-cpu Kunpeng-920
					-bios $bios
					${nic[@]}
			)
			;;
		qemu-kvm)
			[ "$(arch)" == "aarch64" ] && arch_option=(
					-machine virt-4.0,accel=kvm,gic-version=3
					-cpu Kunpeng-920
					-bios $bios
					${nic[@]}
			)
			[ "$(arch)" == "x86_64" ] && arch_option=(
					-bios $bios
					${nic[@]}
			)
			;;
		qemu-system-x86_64)
			arch_option=(
					-bios $bios
					${nic[@]}
			)
			;;
		qemu-system-riscv64)
			arch_option=(
					-machine virt
					-device $device
					-netdev $netdev
			)
			;;
		*)
			echo "qemu not found: $qemu"
			exit
			;;
	esac
}

watch_oops()
{
	tail -f $log_file | grep -q "${oops_patterns[@]}" && {
		sleep 1
		kill $(<qemu.pid)
		echo "Detected kernel oops, killing qemu" >> $log_file
	}
}

run_qemu()
{
	if [ "$DEBUG" == "true" ];then
		"${kvm[@]}" "${arch_option[@]}" --append "${append}"
	else
		# The default value of serial in QEMU is stdio.
		# We use >> and 2>&1 to record serial, stdout, and stderr together to log_file
		"${kvm[@]}" "${arch_option[@]}" --append "${append}" >> $log_file 2>&1
	fi

	local return_code=$?
	[ $return_code -eq 0 ] || echo "[ERROR] qemu start return code is: $return_code" >> $log_file
}

set_options()
{
	set_bios
	set_helper
	set_mac
	set_nic
	set_device
	set_netdev
	set_qemu
}

write_dmesg_flag()
{
	if [ "$1" == "start" ];then
		log_info "starting QEMU: $hostname" | tee $log_file
		cat $ipxe_script >> ${log_file}
		vm_start_time=$(date "+%s")
	else
		vm_end_time=$(date "+%s")
		log_info "Total QEMU duration:  $(( ($vm_end_time - $vm_start_time) / 60 )) minutes" | tee -a $log_file
	fi
}

custom_vm_info()
{
	gzip -dc job.cgz | cpio -div

	nr_node=1
	nr_cpu=1
	memory=8G
	unset cpu_model

	job_fields=(
			-e nr_
			-e cpu
			-e memory
			-e qemu_prefix
			-e RESULT_WEBDAV_HOST
			-e RESULT_WEBDAV_PORT
			-e result_root
	)

	grep "${job_fields[@]}" lkp/scheduled/job.yaml > lkp/scheduled/job_vm.yaml
	create_yaml_variables "lkp/scheduled/job_vm.yaml"
}

upload_dmesg()
{
	local id=$job_id
	local JOB_RESULT_ROOT=$result_root

	upload_files_curl $log_file
}

set_upload_info()
{
  result_root=$(grep "result_root" lkp/scheduled/job.yaml | awk '{print $2}')
  host=$(grep "RESULT_WEBDAV_HOST" lkp/scheduled/job.yaml | awk '{print $2}')
  port=$(grep "RESULT_WEBDAV_PORT" lkp/scheduled/job.yaml | awk '{print $2}')
  job_id=${result_root##*/}
  upload_url="http://${host}:${port}${result_root}/dmesg"
}

upload_dmesg()
{
  [ -n "$job_id" ] || return

  curl -sSf -F "file=@${log_file};filename=dmesg" ${upload_url} --cookie "JOBID=${job_id}"
}

check_logfile
write_logfile

parse_ipxe_script
custom_vm_info
set_upload_info

check_kernel
write_dmesg_flag 'start'
check_initrds

set_options

print_message

public_option
add_disk
individual_option

watch_oops &
watch_pid=$!
run_qemu
kill $watch_pid 2>/dev/null
write_dmesg_flag 'end'
upload_dmesg
