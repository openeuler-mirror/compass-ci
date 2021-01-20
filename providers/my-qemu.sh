#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

: ${LKP_SRC:="/c/lkp-tests"}

source ${LKP_SRC}/lib/log.sh

help()
{
	cat <<-'EOF'
	Usage: ./my-qemu.sh [OPTION]...
	Request scheduler service whether there is a job, then start a local vm if there is a job.
	Scheduler api: http://${SCHED_HOST}:${SCHED_PORT}/boot.ipxe/mac/${mac}

	Mandatory arguments to long options are mandatory for short options too.
	  -h, --help		display this help and exit
	  -d, --debug		open the local vm serial port in the current shell
	EOF

	exit 0
}

while true
do
	[ $# -eq 0 ] && break
	case "$1" in
		-h|--help)
			help;;
		-d|--debug)
			export DEBUG=true;;
		*)
			log_error "Unknown param: $1"
			help
			exit 1;;
	esac
	shift
done

[[ $tbox_group ]] ||
tbox_group=vm-2p8g
export hostname=$tbox_group.$USER-$$
# specify which queues will be request, use " " to separate more than 2 values
export queues="$tbox_group~$USER"

$CCI_SRC/providers/qemu.sh
