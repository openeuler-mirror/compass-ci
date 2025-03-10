#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - nr_cpu
# - memory

source ${CCI_SRC}/lib/log.sh
source ${LKP_SRC}/lib/yaml.sh

: ${nr_cpu:=1}
: ${memory:=1G}

check_env_var() {
    local var_name=$1
    if [ -z "${!var_name}" ]; then
        echo "Warning: environment variable $var_name is not set."
    fi
}

# User set env vars
# check_env_var "ENABLE_PACKAGE_CACHE" # optional
# check_env_var "DEBUG" # optional

# qemu.rb passed env vars
check_env_var "append"
# check_env_var "cpu_model" # optional
check_env_var "hdd_partitions"
check_env_var "hostname"
check_env_var "initrds"
check_env_var "job_id"
check_env_var "kernel"
check_env_var "memory"
check_env_var "nr_cpu"
check_env_var "os"
check_env_var "osv"
check_env_var "rootfs_disk"

# multi-qemu-docker set env vars
check_env_var "PACKAGE_CACHE_DIR"
check_env_var "CCI_SRC"
check_env_var "LKP_SRC"
check_env_var "PIDS_DIR"
check_env_var "host_dir"
check_env_var "log_file"

# env when run as lkp-tests job
# check_env_var "mount_points" # optional

# not env, but keep same with multi-qemu-docker
# JOB_DONE_FIFO_PATH

oops_patterns=(
	-e 'Kernel panic - not syncing:'
	-e 'NULL pointer dereference'

	# /c/linux/arch/arm64/mm/fault.c
	-e 'Unable to handle kernel '

	# /c/linux/arch/x86/mm/fault.c
	-e 'BUG: unable to handle page fault'
)

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
		cat $initrds > concatenated-initrd.cgz
	else
		log_error "The current initrds is null." | tee -a $log_file
		exit 1
	fi
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

set_nr_nic()
{
	[[ -z "$job_id" ]] && {
		job_id=$(awk -F'/' '/pending-jobs/{print $(NF-1)}' $ipxe_script)
		nr_nic=$(awk -F'=' '/^# nr_nic=/{print $2}' $ipxe_script)
	}

	nr_nic=${nr_nic:-1}

	if [ "$nr_nic" -gt 5 ]; then
		echo "nr_nic is greater than 5. set nr_nic=5."
		nr_nic=5
	fi
}

set_nic()
{
	local br="br0"
	[ -f "/sys/class/net/${br}/address" ] || return

	netdev="-netdev bridge,br=br0,id=net2,helper=${helper}"
	for i in $(seq 1 $nr_nic)
	do
		nic[$i]="-nic tap,model=virtio-net-pci,helper=${helper},br=${br}"
	done
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

show_kernel_info()
{
	log_info kernel: $kernel | tee -a $log_file
	log_info initrds: $initrds | tee -a $log_file
	log_info append: $append | tee -a $log_file
	[ -z "$DEBUG" ] && log_info less $log_file
}

common_option()
{
	kvm=(
		$qemu_prefix
		$qemu
		-enable-kvm
		-name guest=$hostname,process=$job_id
		-kernel $kernel
		-initrd concatenated-initrd.cgz
		-smp $nr_cpu
		-m $memory
		-rtc base=localtime
		-k en-us
		-virtfs local,path=$host_dir/result_root,mount_tag=9p/result_root,security_model=none,id=result_root.$job_id
		-netdev user,id=net0 -device virtio-net,netdev=net0
		-netdev user,id=net1 -device e1000,netdev=net1
		${netdev}
		${nic[@]}
		-no-reboot
		-monitor null
		-serial stdio
		-serial unix:$host_dir/qemu-console.sock,server=on,wait=off
		-pidfile $PIDS_DIR/qemu-$hostname.pid
	)
}

cache_option()
{
	[ -n "$ENABLE_PACKAGE_CACHE" ] &&
	case "$os" in
		debian|ubuntu)
			mkdir -p $PACKAGE_CACHE_DIR/$osv/archives
			mkdir -p $PACKAGE_CACHE_DIR/$osv/lists
			kvm+=(-virtfs local,path=$PACKAGE_CACHE_DIR/$osv/archives,mount_tag=9p/package_cache,security_model=mapped-xattr,id=package_cache.$job_id)
			kvm+=(-virtfs local,path=$PACKAGE_CACHE_DIR/$osv/lists,mount_tag=9p/package_cache_index,security_model=mapped-xattr,id=package_cache_index.$job_id)
			;;
		openeuler|centos|rhel|fedora)
			mkdir -p $PACKAGE_CACHE_DIR/$osv
			kvm+=(-virtfs local,path=$PACKAGE_CACHE_DIR/$osv,mount_tag=9p/package_cache,security_model=mapped-xattr,id=package_cache.$job_id)
			;;
	esac

	[ -n "$cache_dirs" ] && kvm+=(-virtfs local,path=$CACHE_DIR,mount_tag=9p/cache,security_model=mapped-xattr,id=cache.$job_id)
}

arch_option()
{
	case "$qemu" in
		qemu-system-aarch64)
			arch_option=(
					-machine virt-4.0,accel=kvm,gic-version=3
			)
			;;
		qemu-kvm)
			[ "$(arch)" == "aarch64" ] && arch_option=(
					-machine virt-4.0,accel=kvm,gic-version=3
			)
			[ "$(arch)" == "x86_64" ] && arch_option=(
			)
			;;
		qemu-system-x86_64)
			arch_option=(
			)
			;;
		qemu-system-riscv64)
			arch_option=(
					-machine virt
			)
			;;
		*)
			echo "qemu not found: $qemu"
			exit
			;;
	esac

	case "$(arch)" in
		aarch64)
			bios=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd
			[ -z "$cpu_model" ] && cpu_model=Kunpeng-920
			;;
		x86_64)
			bios=/usr/share/ovmf/OVMF.fd
			;;
	esac

	[ -n "$bios" ] && [ -e "$bios" ] && arch_option+=(-bios $bios)

	[ -z "$cpu_model" ] && cpu_model=host
	arch_option+=(-cpu "$cpu_model")
}

debug_option()
{
	[ -z "$DEBUG" ] && kvm+=(-nographic)
}

watch_oops()
{
	tail -f $log_file | grep -q "${oops_patterns[@]}" && {
		sleep 1
		kill $(<$PIDS_DIR/qemu-$hostname.pid)
		echo "Detected kernel oops, killing qemu" >> $log_file
	}
}

show_qemu_cmd()
{
    # Helper function to format arrays
    format_array() {
        local array_name="$1"
        shift
        local array=("$@")
        local i=0
        local output=()

        echo "# Define the $array_name array"
        echo "$array_name=("
        while [ $i -lt ${#array[@]} ]; do
            # Check if the current item starts with a dash (indicating an option)
            if [[ "${array[$i]}" == -* ]]; then
                # Start a new line with the option
                output+=("    ${array[$i]}")
                ((i++))
                # Append subsequent items until the next option or end of array
                while [ $i -lt ${#array[@]} ] && [[ "${array[$i]}" != -* ]]; do
                    output[-1]+=" ${array[$i]}"
                    ((i++))
                done
            else
                # If it's not an option, treat it as a standalone item
                output+=("    ${array[$i]}")
                ((i++))
            fi
        done
        # Print the formatted array
        for line in "${output[@]}"; do
            echo "$line"
        done
        echo ")"
    }

    # Generate kvm array
    format_array "kvm" "${kvm[@]}"

    echo ""

    # Generate arch_option array
    format_array "arch_option" "${arch_option[@]}"

    echo ""

    echo "# Define the append variable"
    echo "append=\"$append\""

    echo ""

    echo "# Reconstruct the full command"
    echo '"${kvm[@]}" "${arch_option[@]}" --append "${append}"'
}

run_qemu()
{
	if [ -n "$DEBUG" ];then
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
	set_helper
	set_nr_nic
	set_nic
	set_qemu
}

write_dmesg_flag()
{
	if [ "$1" == "start" ];then
		log_info "starting QEMU: $hostname" >> $log_file
		cat $ipxe_script >> ${log_file}
		vm_start_time=$(date "+%s")
	else
		vm_end_time=$(date "+%s")
		log_info "Total QEMU duration:  $(( ($vm_end_time - $vm_start_time) / 60 )) minutes" >> $log_file
	fi
}

ipxe_script=ipxe_script

check_kernel
check_initrds
show_kernel_info

set_options
common_option
arch_option
cache_option
debug_option
add_disk

set -m
watch_oops &

JOB_DONE_FIFO_PATH=/tmp/job_completion_fifo
echo "boot: $job_id" >> $JOB_DONE_FIFO_PATH
write_dmesg_flag 'start'
show_qemu_cmd >> $log_file
run_qemu
write_dmesg_flag 'end'
kill %1
echo "done: $job_id" >> $JOB_DONE_FIFO_PATH
