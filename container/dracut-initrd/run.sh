#!/bin/bash
# create initramfs from specified os lib modules
# input:
#   specified os lib modules directory
# output:
#   initramfs image file of the specified os version

[ -d "$1" ] || {
	echo "Example usage:
		./run.sh /os/debian/aarch64/sid/lib/modules/5.4.0-4-arm64
"
	exit
}

modules_dir=$1
kver=$(basename $modules_dir)
root=${modules_dir%/lib/modules/*}

kernel_modules=/lib/modules/$kver
initrd_output=/boot/initramfs.lkp-${kver}.img

cmd=(
	docker run
	--rm
	-it
	-v $root/boot:/boot
	-v $root/lib/modules:/lib/modules
	debian:dracut
	dracut --force --kver $kver -k $kernel_modules $initrd_output

	# example:
	# dracut --kver 5.4.0-4-arm64 -k /os/debian/aarch64/sid/lib/modules/5.4.0-4-arm64 /os/debian/aarch64/sid/boot/initramfs.lkp-5.4.0-4-arm64.img
)

"${cmd[@]}"
