#!/bin/sh -e

export DEBIAN_FRONTEND=noninteractive

# change apt source repo to 163
apt-get update
apt-get install -y ca-certificates
mv /etc/apt/sources.list.bak /etc/apt/sources.list

apt-get update
apt-get install -y apt-utils nfs-common netbase cifs-utils
apt-get install -y dracut dracut-network dracut-config-generic

apt-get clean
rm -rf /var/lib/apt/lists/*

# Replace the runtime shell script with a custom shell script
cp -a /usr/local/bin/cifs-lib.sh /usr/lib/dracut/modules.d/95cifs/

cat overlay-lkp.sh   >> /usr/lib/dracut/modules.d/90overlay-root/overlay-mount.sh
