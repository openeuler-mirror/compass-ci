#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# - nr_cpu
# - memory

: ${nr_cpu:=1}
: ${memory:=1G}

qemu=qemu-system-aarch64
command -v $qemu >/dev/null || qemu=qemu-kvm

kvm=(
	$qemu
	-machine virt-4.0,accel=kvm,gic-version=3
	-smp $nr_cpu
	-m $memory
	-cpu Kunpeng-920
	-device virtio-gpu-pci
	-bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
	-nic tap,model=virtio-net-pci,helper=/usr/libexec/qemu-bridge-helper,br=br0,mac=${mac}
	-k en-us
	-no-reboot
	-nographic
	-serial stdio
	-monitor null
)
"${kvm[@]}"
