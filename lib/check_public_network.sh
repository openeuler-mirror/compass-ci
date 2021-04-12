#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

public_network_ok()
{
	ping -c 1 -w 1 114.114.114.114 >/dev/null 2>&1
}
