#!/bin/bash -e
# For your reference only.
# It's better to run the below scripts step by step.

[[ $CCI_SRC ]] || export CCI_SRC=$(cd $(dirname $(realpath $0)); git rev-parse --show-toplevel)
cd $CCI_SRC/sparrow || exit

0-package/install.sh
1-storage/tiny.sh
1-storage/permission.sh
2-network/br0.sh
2-network/iptables
2-network/nfs.sh
3-code/git.sh
3-code/dev-env.sh
4-docker/buildall
5-build/ipxe.sh
6-test/qemu.sh
6-test/docker.sh
7-systemd/systemd-setup.sh
