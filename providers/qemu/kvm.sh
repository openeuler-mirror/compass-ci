#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - nr_cpu
# - memory

: ${nr_cpu:=1}
: ${memory:=1G}

source ${CCI_SRC}/lib/log.sh

check_logfile()
{
	log_file=/srv/cci/serial/logs/${hostname}
	[ -f "$log_file" ] || {
		touch $log_file
		# fluentd refresh time is 1s
		# let fluentd to monitor this file first
		sleep 2
	}
}

write_logfile()
{
	ipxe_script=ipxe_script
	curl http://${SCHED_HOST:-172.17.0.1}:${SCHED_PORT:-3000}/boot.ipxe/mac/${mac} > $ipxe_script
	cat $ipxe_script >> ${log_file}
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
				wget --timestamping -a ${log_file} --progress=bar:force $b
				initrds+="$file "
				;;
			kernel)
				kernel=$(basename "$b")
				wget --timestamping -a ${log_file} --progress=bar:force $b
				append=$(echo "$c" | sed -r "s/ initrd=[^ ]+//g")
				;;
			*)
				;;
		esac
	done < $ipxe_script
}

check_kernel()
{
	[ -n "$kernel" ] || {
		log_info "Can not find job for current hostname: $hostname."
		exit 0
	}

	[ -s "$kernel" ] || {
		log_error "Can not find kernel file or kernel file is empty: $kernel."
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
		log_error "The current initrds is null."
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

add_disk()
{
	# VM testbox has disk spec?
	[ -n "$hdd_partitions" ] || [ -n "$rootfs_disk" ] || return 0

	[ -n "$mount_points" ] || mount_points=$(pwd)

	local index=0
	local disk
	for disk in $hdd_partitions $rootfs_disk
	do
		local qcow2_file="${mount_points}/${hostname}-${disk##*/}.qcow2"
		local drive="file=${qcow2_file},media=disk,format=qcow2,index=${index}"
		((index++))

		qemu-img create -q -f qcow2 "${qcow2_file}" 512G
		kvm+=(-drive ${drive})
	done
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
	log_info SCHED_PORT: $SCHED_PORT
	log_info kernel: $kernel
	log_info initrds: $initrds
	log_info append: $append
	[ "$DEBUG" == "true" ] || log_info less $log_file

	sleep 5
}

public_option()
{
	kvm=(
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
	)

	[ "$DEBUG" == "true" ] || kvm=("${kvm[@]}" -serial file:${log_file})
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

run_qemu()
{
	"${kvm[@]}" "${arch_option[@]}" --append "${append}"
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

check_logfile
write_logfile

parse_ipxe_script

check_kernel
check_initrds

set_options

print_message

public_option
add_disk
individual_option

run_qemu
