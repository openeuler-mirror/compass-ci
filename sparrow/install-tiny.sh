#!/bin/bash -e
# For your reference only.
# It's better to run the below scripts step by step.

[[ $CCI_SRC ]] || export CCI_SRC=$(dirname $(dirname $(realpath $0)))
cd $CCI_SRC/sparrow || exit

0-package/install.sh
1-storage/tiny.sh
2-network/br0.sh
2-network/iptables.sh
3-code/git.sh
3-code/dev-env.sh
4-docker/buildall.sh
6-test/docker.sh
