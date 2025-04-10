#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

# Some docker images dont have cpio command
[ "${PATH%%:/opt/busybox:*}" = "$PATH" ] && export PATH="$PATH:/opt/busybox"

# catch cpio failures
set -o pipefail

# cgz files containing /usr/* files have to be unpacked inside container
(
    cd /
    for file in $(ls -1tr /lkp/cpio-for-guest/*.cgz)
    do
        test -e "$file" || continue
        gzip -dc "$file" | cpio -idu >/dev/null
    done
)

test -d /lkp/lkp/src/rootfs/addon/root && {
	mkdir -p /root/.ssh
	cp -r /lkp/lkp/src/rootfs/addon/root/. /root
}

test -d /lkp/lkp/src/rootfs/addon/usr && {
	cp -r /lkp/lkp/src/rootfs/addon/usr/* /usr
}

sh /lkp/lkp/src/rootfs/addon/etc/init.d/lkp-bootstrap
