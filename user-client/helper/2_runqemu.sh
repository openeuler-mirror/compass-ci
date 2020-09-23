#!/usr/bin/env bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

: ${CCI_SRC:=/c/cci}
: ${LKP_SRC:=/c/lkp-tests}

$CCI_SRC/providers/my-qemu.sh
