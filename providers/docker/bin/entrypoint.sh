#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+

sh /lkp/lkp/src/rootfs/addon/etc/init.d/lkp-bootstrap

# if you need keep container active, sleep or ping
sleep 30
# ping 0.0.0.0
