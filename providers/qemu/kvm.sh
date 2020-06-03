#!/bin/bash
# - nr_cpu
# - memory

: ${nr_cpu:=1}
: ${memory:=1G}

qemu=qemu-system-aarch64
command -v $qemu >/dev/null || qemu=qemu-kvm

scheduler=172.17.0.1
port=3000
ipxe_script=$(dirname ${BASH_SOURCE[0]})/ipxe_script
curl http://${scheduler}:${port}/boot.ipxe/mac/${mac} > $ipxe_script
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
			wget $b
			initrds+="$file "
			;;
		kernel)
			file=$(basename "$b")
			#[[ -f $file ]] ||
			rm -f $file
			wget $b
			append=$(echo "$c" | sed -r "s/ initrd=[^ ]+//g")
			;;
		*)
			;;
	esac
#done < /tftpboot/boot.ipxe-debian
#done < /tftpboot/boot.ipxe-centos
done < $ipxe_script

initrd=initrd
cat $initrds > $initrd

echo kernel: $kernel
echo initrds: $initrds
echo append: $append

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
	-serial stdio
	-monitor null
)

"${kvm[@]}" --append "${append}"
