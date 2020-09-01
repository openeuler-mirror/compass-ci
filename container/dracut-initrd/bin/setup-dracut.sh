#!/bin/sh -e
# SPDX-License-Identifier: MulanPSL-2.0+

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends apt-utils >/dev/null 2>&1
apt-get install -y nfs-common netbase cifs-utils kmod
apt-get install -y dracut dracut-network dracut-config-generic

apt-get clean
rm -rf /var/lib/apt/lists/*

# Replace the runtime shell script with a custom shell script
cp -a /usr/local/bin/cifs-lib.sh /usr/lib/dracut/modules.d/95cifs/

cat overlay-lkp.sh   >> /usr/lib/dracut/modules.d/90overlay-root/overlay-mount.sh
