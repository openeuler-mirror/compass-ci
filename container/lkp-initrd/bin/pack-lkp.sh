#!/bin/bash -e
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

export OWNER=root.root
export LKP_USER=lkp
export USER=lkp
TAG=$1

umask 002

[[ -n $TAG ]] && {
	git -C $LKP_SRC tag $TAG
}

$LKP_SRC/sbin/pack -f -a $ARCH lkp-src
