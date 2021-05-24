#!/bin/sh

reboot_with_msg()
{
	echo "[compass-ci reboot] $1"
	reboot
}

analyse_kernel_cmdline_params() {
    rootfs="$(getarg root=)"

    # if root is a local disk, then boot directly.
    [[ $rootfs =~ ^/dev/ ]] && exit 0

    # example: $nfs_server_ip:/os/${os}/${os_arch}/${os_version}-snapshots/20210310005959
    rootfs_src=$(echo $"$rootfs" | sed 's/\///')

    # adapt $nfs_server_ip:/os/${os}/${os_arch}/${os_version}-2021-03-10-00-59-59
    timestamp="$(echo ${rootfs_src//-/} | grep -oE '[0-9]{14}$')"
    [ -n "$timestamp" ] || reboot_with_msg "cannot find right timestamp"

    os="$(echo $rootfs_src | awk -F '/|-' '{print $2}')"
    os_arch="$(echo $rootfs_src | awk -F '/|-' '{print $3}')"

    # replace '-' to '_' in $os_version
    # bacause when we create logical volume, '-' in the logical volume name will be '--'.
    os_version="$(echo $(getarg os_version=) | tr '-' '_')"
    os_info="${os}_${os_arch}_${os_version}"
    [ -n "$os"] || [ -n "$os_arch" ] || [ -n "$os_version" ] || reboot_with_msg "cannot find right os_info: $os_info"

    export rootfs_src timestamp os_info
}

sync_src_lv() {
    local src_lv="$1"
    local vg_name="os"

    [ -e "$src_lv" ] && return

    # if os_mount=local, then 'rootfs_disk' is necessary.
    rootfs_disk="$(getarg rootfs_disk=)"
    [ -n "$rootfs_disk" ] || reboot_with_msg "cannot find rootfs_disk for this testbox."

    # prepare volume group
    local disk
    for disk in $(echo $rootfs_disk | tr ',' ' ')
    do
        # if disk not exist, then reboot
        [ -b "$disk" ] || reboot_with_msg "warn dracut: FATAL: device not found: $disk"

        # if disk is not pv, then pvcreate it.
        lvm pvdisplay $disk > /dev/null || lvm pvcreate -y $disk || reboot_with_msg "create pv failed: $disk"

        # if vg not existed: create it by disk.
        # if vg existed:     add disk to vg,
        if lvm vgdisplay $vg_name > /dev/null; then
            # if pv not in vg: add disk to vg
            lvm pvdisplay $disk | grep 'VG Name' | grep -w $vg_name || {
                lvm vgextend -y $vg_name $disk || reboot_with_msg "vgextend failed: $disk"
            }
        else
            lvm vgcreate -y $vg_name $disk || reboot_with_msg "vgcreate failed: $disk"
        fi
    done

    lvm vgs "$vg_name" || reboot_with_msg "warn dracut: FATAL: vg $vg_name not found"

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
    [ -e "$src_lv" ] || reboot_with_msg "warn dracut: FATAL: no src_lv with local mount"
fi

save_root_partition="$(getarg save_root_partition=)"
if [ -z "$save_root_partition" ]; then
    boot_lv="/dev/mapper/os-${os_info}"
else
    boot_lv="$save_root_partition"
fi

snapshot_boot_lv "$src_lv" "$boot_lv"

set_sysroot "$boot_lv"

[ "$CCI_NO_SUNRPC" == "true" ] && {
	umount /var/lib/nfs/rpc_pipefs
	rmmod nfsv4 nfs rpcsec_gss_krb5 auth_rpcgss lockd sunrpc
}

exit 0
