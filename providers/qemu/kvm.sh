#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# - nr_cpu
# - memory

: ${nr_cpu:=1}
: ${memory:=1G}

log_file=/srv/cci/serial/logs/${hostname}
qemu=qemu-system-aarch64
command -v $qemu >/dev/null || qemu=qemu-kvm

echo $SCHED_PORT
ipxe_script=ipxe_script
curl http://${SCHED_HOST:-172.17.0.1}:${SCHED_PORT:-3000}/boot.ipxe/mac/${mac} > $ipxe_script
cp $ipxe_script ${log_file}
#echo -----
#cat $ipxe_script
#echo -----
#exit

append=
initrds=
while read a b c
do
	case "$a" in
		'#')
			;;
		initrd)
			file=$(basename "$b")
			rm -f $file
			wget -a ${log_file} --progress=bar:force $b
			initrds+="$file "
			;;
		kernel)
			kernel=$(basename "$b")
			#[[ -f $kernel ]] ||
			rm -f $kernel
			wget -a ${log_file} --progress=bar:force $b
			append=$(echo "$c" | sed -r "s/ initrd=[^ ]+//g")
			;;
		*)
			;;
	esac
#done < /tftpboot/boot.ipxe-debian
#done < /tftpboot/boot.ipxe-centos
done < $ipxe_script

[ -n "$initrds" ] || {
	exit
}

initrd=initrd
cat $initrds > $initrd

echo kernel: $kernel
echo initrds: $initrds
echo append: $append
echo less $log_file

kvm=(
	$qemu
	-machine virt-4.0,accel=kvm,gic-version=3
	-kernel $kernel
	-initrd $initrd
	-smp $nr_cpu
	-m $memory
	-cpu Kunpeng-920
	-device virtio-gpu-pci
	-bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
	-nic tap,model=virtio-net-pci,helper=/usr/libexec/qemu-bridge-helper,br=br0,mac=${mac}
	-k en-us
	-no-reboot
	-nographic
	-serial file:${log_file}
	-monitor null
)

"${kvm[@]}" --append "${append}"
