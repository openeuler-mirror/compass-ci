#!/bin/sh -e

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y apt-utils nfs-common netbase
apt-get install -y dracut dracut-network dracut-config-generic

apt-get clean
rm -rf /var/lib/apt/lists/*

cat overlay-lkp.sh   >> /usr/lib/dracut/modules.d/90overlay-root/overlay-mount.sh
