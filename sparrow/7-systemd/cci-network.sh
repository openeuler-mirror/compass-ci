#!/bin/bash
#this file used in our own systemd unit file: cci-network.service.
#contents as follows will be automatically executed after system reboot.

[[ $CCI_SRC ]] || CCI_SRC=/c/crystal-ci

$CCI_SRC/sparrow/2-network/br0.sh
$CCI_SRC/sparrow/2-network/iptables
$CCI_SRC/sparrow/2-network/nfs.sh

# --restart=always option is not absolutely reliable
containers=($(docker ps -a |grep -v NAMES |awk '{print $NF}'))
[ -n "$containers" ] && docker start "${containers[@]}" >/dev/null 2>&1
