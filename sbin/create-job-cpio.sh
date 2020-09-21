#!/bin/bash -e
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
#
# input files: $1/job.sh $1/job.yaml
# output file: $1/job.cgz

cd "$1" || exit

install -m775 -D -t lkp/scheduled job.sh
install -m664 -D -t lkp/scheduled job.yaml

find lkp | cpio --quiet -o -H newc | gzip > job.cgz

rm -fr ./lkp
