#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

test -d /lkp/lkp/src/rootfs/addon/root && {
	mkdir -p /root/.ssh
	cp -r /lkp/lkp/src/rootfs/addon/root/. /root
}

test -d /lkp/lkp/src/rootfs/addon/usr && {
	cp -r /lkp/lkp/src/rootfs/addon/usr/* /usr
}

sh /lkp/lkp/src/rootfs/addon/etc/init.d/lkp-bootstrap
