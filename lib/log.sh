#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

log_info()
{
	date +"[INFO] %F %T ${0##*/}: $*"
}

log_debug()
{
	date +"[DEBUG] %F %T ${0##*/}: $*"
}

log_warn()
{
	date +"[WARN] %F %T ${0##*/}: $*" >&2
}

log_error()
{
	date +"[ERROR] %F %T ${0##*/}: $*" >&2
}
