#!/bin/sh -e
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --fix-missing --no-install-recommends apt-utils >/dev/null 2>&1
apt-get install -y --fix-missing nfs-common netbase cifs-utils kmod rsync
apt-get install -y --fix-missing dracut dracut-network dracut-config-generic

apt-get clean
rm -rf /var/lib/apt/lists/*

# Replace the runtime shell script with a custom shell script
cp -a /usr/local/bin/cifs-lib.sh /usr/lib/dracut/modules.d/95cifs/

cat overlay-lkp.sh   >> /usr/lib/dracut/modules.d/90overlay-root/overlay-mount.sh
sed -i "/install() {/ainst /usr/bin/awk" /usr/lib/dracut/modules.d/40network/module-setup.sh
