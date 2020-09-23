#!/bin/sh -e
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

apk add bash gcc make libc-dev findutils cpio gzip
adduser -Du 1090 lkp # lkp group also created
