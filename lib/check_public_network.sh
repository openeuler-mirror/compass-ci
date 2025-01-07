#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

public_network_ok()
{
	ping -c 1 -W 10 8.8.8.8 >/dev/null 2>&1 || \
	ping -c 1 -W 10 114.114.114.114 >/dev/null 2>&1 || \
	ping -c 1 -W 10 compass-ci.openeuler.org >/dev/null 2>&1 || \
	curl -k -s -m 10 --retry-delay 2 --retry 5 https://compass-ci.openeuler.org/ -o /dev/null
}
