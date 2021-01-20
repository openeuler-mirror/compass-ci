#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - nr_cpu
# - memory

: ${nr_cpu:=1}
: ${memory:=1G}
: ${LKP_SRC:="/c/lkp-tests"}

source ${LKP_SRC}/lib/log.sh

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

check_option_value()
{
	[ -n "$kernel" ] || {
		log_info "Can not find job for current hostname: $hostname."
		exit 0
	}

	[ -s "$kernel" ] || {
		log_error "Can not find kernel file or kernel file is empty: $kernel."
		exit 1
	}
	
	# debian has both qemu-system-x86_64 and qemu-system-riscv64 command
	[[ $kernel =~ 'riscv64' ]] && qemu=qemu-system-riscv64

	[ -n "$initrds" ] || {
		log_error "The current initrds is null."
		exit 1
	}
}

set_initrd()
{
	initrd=initrd
	cat $initrds > $initrd
}

set_bios()
{
       bios=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd
       [ -f "$bios" ] || bios=/usr/share/ovmf/OVMF.fd
}

set_helper()
{
       helper=/usr/libexec/qemu-bridge-helper
       [ -f "$helper" ] || helper=/usr/lib/qemu/qemu-bridge-helper
}

set_nic()
{
       nic="tap,model=virtio-net-pci,helper=$helper,br=br0,mac=${mac}"
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

	for qemu in "${qemus[@]}"
	do
		command -v "$qemu" > /dev/null && break
	done
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
		-kernel $kernel
		-initrd $initrd
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
					-nic $nic
			)
			;;
		qemu-kvm)
			[ "$(arch)" == "aarch64" ] && arch_option=(
					-machine virt-4.0,accel=kvm,gic-version=3
					-cpu Kunpeng-920
					-bios $bios
					-nic $nic
			)
			[ "$(arch)" == "x86_64" ] && arch_option=(
					-bios $bios
					-nic $nic
			)
			;;
		qemu-system-x86_64)
			arch_option=(
					-bios $bios
					-nic $nic
			)
			;;
		qemu-system-riscv64)
			arch_option=(
					-machine virt
					-device $device
					-netdev $netdev
			)
			;;
	esac
}

run_qemu()
{
	"${kvm[@]}" "${arch_option[@]}" --append "${append}"
}

set_options()
{
	set_initrd
	set_bios
	set_helper
	set_nic
	set_device
	set_netdev
	set_qemu
}

check_logfile
write_logfile

parse_ipxe_script

set_options
check_option_value

print_message

public_option
individual_option

run_qemu
