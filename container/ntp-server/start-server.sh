#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

/usr/sbin/ntpd -g -l /var/log/ntpstats/ntpd.log 

exec "$@"
