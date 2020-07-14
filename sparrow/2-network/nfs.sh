#!/bin/bash

modprobe nfs
modprobe nfsd

[[ -f /etc/modules-load.d/cci-nfs.conf ]] ||
cat > /etc/modules-load.d/cci-nfs.conf <<EOF
nfs
nfsd
EOF
