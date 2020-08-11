#!/bin/bash -e
# SPDX-License-Identifier: MulanPSL-2.0+

[[ $ARCH 	]] || ARCH=$(uname -m)
[[ $LKP_SRC	]] || LKP_SRC=/c/lkp-tests

export OWNER=root.root
export LKP_USER=lkp
export USER=lkp

umask 002
$LKP_SRC/sbin/pack -f -a $ARCH lkp-src
