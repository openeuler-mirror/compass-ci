#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - nr_cpu
# - memory

: ${nr_cpu:=1}
: ${memory:=1G}
: ${log_dir:=/srv/provider/logs}

source ${CCI_SRC}/lib/log.sh
source ${LKP_SRC}/lib/yaml.sh

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
		qemu-img create -q -f qcow2 "${qcow2_file}" "${disk_size}"
	else
		[ -f "$qcow2_file" ] || qemu-img create -q -f qcow2 "${qcow2_file}" "${disk_size}"
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
	disk_encode_length=${#disk_encode[@]}

	# create rootfs disk
	create_disk 0 "/dev/vda"

	nr_disk=$(awk -F'=' '/^# nr_disk=/{print $2}' $ipxe_script)

	if([ -n "$nr_disk" ]); then
		for((i=0;i<$nr_disk;i++)); do
			if [ "$i" -ge "$disk_encode_length" ]; then
				break
			fi

			disk=${disk_encode[$i]}
			create_disk $((i+1)) $disk
		done
	else
		local index=1
		if([ -n "$nr_hdd_partitions" ]); then
			for((i=0;i<$nr_hdd_partitions;i++)); do
				disk=${disk_encode[$index-1]}
				create_disk $index $disk
				((index++))
			done
		else
			for disk in ${hdd_partitions[@]}; do
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
	fi
}

create_disk()
{
	local index=$1
	local disk=$2

	disk_size=$(awk -F'=' '/^# disk_size=/{print $2}' $ipxe_script)

	if [ -n "$disk_size" ]; then
		if [[ "$disk_size" =~ ^[0-9]+$ ]]; then
			disk_size="${disk_size}G"
		fi

		if [ ${disk_size: -1} != "G" ] && [ ${disk_size: -1} != "g" ]; then
			disk_size="128G"
		fi

		disk_size_num=$(echo "$disk_size" | tr '[:upper:]' '[:lower:]' | sed 's/[g]//')
		if [ $disk_size_num -gt 128 ]; then
        	disk_size="128G"
    	fi
	else
		disk_size="128G"
	fi

	if [ "$index" -eq 0 ]; then
		prepare_disk "128G" "true"
	else
		prepare_disk $disk_size "true"
	fi

	# about if=virtio:
	# - let the qemu recognize disk as virtio_blk, then the device name will be /dev/vd[a-z].
	# - to avoid the given device name is not the same as the real device name.
	local drive="file=${qcow2_file},media=disk,format=qcow2,index=${index},if=virtio"
	kvm+=(-drive ${drive})
}

set_mac()
{
	job_id=$(awk -F'/' '/pending-jobs/{print $(NF-1)}' $ipxe_script)
	nr_nic=$(awk -F'=' '/^# nr_nic=/{print $2}' $ipxe_script)

	mac_arr[1]=$mac
	nr_nic=${nr_nic:-1}

	if [ "$nr_nic" -gt 5 ]; then
		echo "nr_nic is greater than 5. set nr_nic=5."
		nr_nic=5
	fi

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
		br="br0"
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
		-virtfs local,path=$host_dir/result_root,mount_tag=9p/result_root,security_model=none,id=$job_id/result_root
		-no-reboot
		-nographic
		-monitor null
		-serial stdio
		-serial unix:$host_dir/qemu-console.sock,server=on,wait=off
		-pidfile $PIDS_DIR/qemu-$hostname.pid
	)

	[ -n "$cpu_model" ] && kvm+=(-cpu "$cpu_model")
}

cache_option()
{
	[ -n "$ENABLE_PACKAGE_CACHE" ] &&
	case "$os" in
		debian|ubuntu)
			mkdir -p $CACHE_DIR/$osv/archives
			mkdir -p $CACHE_DIR/$osv/list
			kvm+=(-virtfs local,path=$CACHE_DIR/$osv/archives,mount_tag=9p/package_cache,security_model=none,id=$job_id/package_cache)
			kvm+=(-virtfs local,path=$CACHE_DIR/$osv/lists,mount_tag=9p/package_cache_index,security_model=none,id=$job_id/package_cache)
			;;
		openeuler|centos|rhel|fedora)
			mkdir -p $CACHE_DIR/$osv
			kvm+=(-virtfs local,path=$CACHE_DIR/$osv,mount_tag=9p/package_cache,security_model=none,id=$job_id/package_cache)
			;;
	esac
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
		kill $(<$PIDS_DIR/qemu-$hostname.pid)
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

check_logfile
ipxe_script=ipxe_script

check_kernel
check_initrds

set_options

print_message

public_option
cache_option
add_disk
individual_option

set -m
watch_oops &

JOB_DONE_FIFO_PATH=/tmp/job_completion_fifo
echo "boot: $job_id" >> $JOB_DONE_FIFO_PATH
write_dmesg_flag 'start'
run_qemu
write_dmesg_flag 'end'
kill %1
echo "done: $job_id" >> $JOB_DONE_FIFO_PATH
