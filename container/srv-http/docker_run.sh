#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

mount_ssl(){
	if [ -f "/etc/ssl/certs/web-backend.key" ] && [ -f "/etc/ssl/certs/web-backend.crt" ]; then
		echo "-v /etc/ssl/certs:/opt/cert"
	fi
}
