#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

mkdir -p /root/.ssh
cp /lkp/lkp/src/rootfs/addon/root/.ssh/id_rsa /root/.ssh/
sh /lkp/lkp/src/rootfs/addon/etc/init.d/lkp-bootstrap
