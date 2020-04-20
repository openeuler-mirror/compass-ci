#!/bin/bash -e

[[ $ARCH 	]] || ARCH=$(uname -m)
[[ $LKP_SRC	]] || LKP_SRC=/c/lkp-tests

export OWNER=root.root
export LKP_USER=lkp
export USER=lkp

$LKP_SRC/sbin/pack -f -a $ARCH lkp-src
