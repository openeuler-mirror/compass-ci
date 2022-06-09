#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

declare -A LOG_LEVEL_DICT
LOG_LEVEL_DICT=(
	["ERROR"]=4
	["WARNING"]=3
	["INFO"]=2
	["DEBUG"]=1
)

[ -n "$LOG_LEVEL" ] || LOG_LEVEL="INFO"

log_debug()
{
	[ ${LOG_LEVEL_DICT[$LOG_LEVEL]} -le ${LOG_LEVEL_DICT[DEBUG]} ] || return 0

	date +"[DEBUG] %F %T ${0##*/}: $*"
}

log_info()
{
	[ ${LOG_LEVEL_DICT[$LOG_LEVEL]} -le ${LOG_LEVEL_DICT[INFO]} ] || return 0

	date +"[INFO] %F %T ${0##*/}: $*"
}

log_warn()
{
	[ ${LOG_LEVEL_DICT[$LOG_LEVEL]} -le ${LOG_LEVEL_DICT[WARNING]} ] || return 0

	date +"[WARN] %F %T ${0##*/}: $*" >&2
}

log_error()
{
	[ ${LOG_LEVEL_DICT[$LOG_LEVEL]} -le ${LOG_LEVEL_DICT[ERROR]} ] || return 0

	date +"[ERROR] %F %T ${0##*/}: $*" >&2
}

die()
{
	log_error "$@"
	exit 1
}
