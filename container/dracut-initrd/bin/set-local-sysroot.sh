#!/bin/sh

analyse_kernel_cmdline_params() {
    rootfs="$(getarg root=)"
    # example: $nfs_server_ip:/os/${os}/${os_arch}/${os_version}-snapshots/20210310005959
    rootfs_src=$(echo $"$rootfs" | sed 's/\///')
    timestamp="$(basename $rootfs_src)"
    os="$(echo $rootfs_src | awk -F '/|-' '{print $2}')"
    os_arch="$(echo $rootfs_src | awk -F '/|-' '{print $3}')"
    os_version="$(echo $rootfs_src | awk -F '/|-' '{print $4}')"
    os_info="${os}_${os_arch}_${os_version}"
    export rootfs_src timestamp os_info
}

sync_src_lv() {
    local src_lv="$1"

    [ -e "$src_lv" ] && return

    # create logical volume
    src_lv_devname="$(basename $src_lv)"
    lvm lvcreate -y -L 10G --name "${src_lv_devname#os-}" os
    mke2fs -t ext4 -F "$src_lv"

    # sync nfsroot to $src_lv
    mkdir -p /mnt1 && mount -t nfs "$rootfs_src" /mnt1
    mkdir -p /mnt2 && mount "$src_lv" /mnt2
    cp -a /mnt1/. /mnt2/
    umount /mnt1 /mnt2

    # change permission of "$src_lv" to readonly
    lvm lvchange --permission r "$src_lv"
}

snapshot_boot_lv() {
    local src_lv="$1"
    local boot_lv="$2"

    [ "$src_lv" == "$boot_lv" ] && return

    lvm lvremove --force "$boot_lv"
    boot_lv_devname="$(basename $boot_lv)"
    lvm lvcreate --size 10G --name ${boot_lv_devname#os-} --snapshot "$src_lv"
}

set_sysroot() {
    boot_lv="$1"
    umount "$NEWROOT"
    mount "$boot_lv" "$NEWROOT"
}

if ! getargbool 0 local; then
    exit 0
fi

analyse_kernel_cmdline_params

sed -i "s/^locking_type = .*/locking_type = 1/" /etc/lvm/lvm.conf

use_root_partition="$(getarg use_root_partition=)"
if [ -z "$use_root_partition" ]; then
    src_lv="/dev/mapper/os-${os_info}_$timestamp"
    sync_src_lv "$src_lv"
else
    src_lv="$use_root_partition"
    [ -e "$src_lv" ] || {
        echo "warn dracut: FATAL: no src_lv with local mount, reboot"
        reboot
    }
fi

save_root_partition="$(getarg save_root_partition=)"
if [ -z "$save_root_partition" ]; then
    boot_lv="/dev/mapper/os-${os_info}"
else
    boot_lv="$save_root_partition"
fi

snapshot_boot_lv "$src_lv" "$boot_lv"

set_sysroot "$boot_lv"

exit 0
