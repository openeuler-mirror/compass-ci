#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

[[ $tbox_group ]] ||
tbox_group=vm-2p8g
export hostname=$tbox_group.$USER-$$
# specify which queues will be request, use " " to separate more than 2 values
export queues="$tbox_group~$USER"

$CCI_SRC/providers/qemu.sh
