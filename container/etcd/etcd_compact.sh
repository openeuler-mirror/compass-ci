#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

rev=$(etcdctl endpoint status --write-out="json"|egrep -o '"revision":[0-9]*'|egrep -o '[0-9].*')

KEEP=10000 # keep 10k revision history
[ $rev -gt $KEEP ] || exit 0
rev=$((rev-$KEEP))

etcdctl compact $rev

[ $(date +%A) = Sunday ] && etcdctl --command-timeout=30s defrag
