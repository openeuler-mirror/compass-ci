#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

umask 002
/usr/local/openresty/bin/openresty -g 'daemon off;'
