#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - nr_cpu
# - memory

source ${CCI_SRC}/lib/log.sh

: ${nr_cpu:=1}
: ${memory:=1G}

serial_log=/srv/cci/serial/logs/${hostname}
if [ ! -f "$serial_log" ]; then
	touch $serial_log
	# fluentd refresh time is 1s
	# let fluentd to monitor this file first
	sleep 2
fi

qemu=qemu-system-aarch64
command -v $qemu >/dev/null || qemu=qemu-kvm

[ "$DEBUG" == "true" ] || log_info less $serial_log

kvm=(
	$qemu
	-machine virt-4.0,accel=kvm,gic-version=3
	-smp $nr_cpu
	-m $memory
	-cpu Kunpeng-920
	-device virtio-gpu-pci
	-bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
	-rtc base=localtime
	-nic tap,model=virtio-net-pci,helper=/usr/libexec/qemu-bridge-helper,br=br0,mac=${mac}
	-k en-us
	-no-reboot
	-nographic
	-monitor null
)

[ "$DEBUG" == "true" ] || kvm=("${kvm[@]}" -serial file:${serial_log})

"${kvm[@]}"
