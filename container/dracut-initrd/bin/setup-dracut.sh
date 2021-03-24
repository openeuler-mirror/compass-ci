#!/bin/sh -e
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --fix-missing --no-install-recommends -qq apt-utils \
nfs-common netbase cifs-utils kmod rsync dracut dracut-network xz-utils \
dracut-config-generic lvm2 xz-utils systemd-sysv

apt-get clean
rm -rf /var/lib/apt/lists/*

# Replace the runtime shell script with a custom shell script
cp -a /usr/local/bin/cifs-lib.sh /usr/lib/dracut/modules.d/95cifs/

cat overlay-lkp.sh   >> /usr/lib/dracut/modules.d/90overlay-root/overlay-mount.sh
sed -i "/install() {/a\    inst /usr/bin/awk" /usr/lib/dracut/modules.d/40network/module-setup.sh
tools_00bash="/sbin/e2fsck /sbin/mke2fs /usr/bin/basename /sbin/lvm /sbin/reboot"
sed -i "/install() {/a\    inst $tools_00bash" /usr/lib/dracut/modules.d/00bash/module-setup.sh

pre_mount_file="/usr/lib/dracut/modules.d/98dracut-systemd/dracut-pre-mount.sh"
[ "$(sed -n '$p' $pre_mount_file)"  = "exit 0" ] && sed -i '$d' "$pre_mount_file"
cat set-local-sysroot.sh >> "$pre_mount_file"
