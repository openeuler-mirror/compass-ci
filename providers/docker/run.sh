#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

: ${job_id:=$$}
: ${docker_image:="centos:7"}
: ${load_path:="${HOME}/jobs"}
: ${hostname:="dc-8g-1"}
: ${log_dir:="/srv/cci/serial/logs/$hostname"}

if [[ $hostname =~ ^(.*)-[0-9]+$ ]]; then
	tbox_group=${BASH_REMATCH[1]}
else
	tbox_group=$hostname
fi
host=${tbox_group%.*}

[ -n "$nr_cpu" ] || nr_cpu=$(grep '^nr_cpu: ' $LKP_SRC/hosts/${host} | cut -f2 -d' ')
[ -n "$memory" ] || memory=$(grep '^memory: ' $LKP_SRC/hosts/${host} | cut -f2 -d' ')

check_busybox()
{
	local list
	list=($(type -a busybox | xargs | awk '{gsub("busybox is ", ""); print $0}'))
	busybox_path=$(command -v busybox)

	for i in ${list[@]}
	do
		if ${i} --list | grep -wq wget; then
			busybox_path="${i}"
			break
		fi
	done
}

DIR=$(dirname $(realpath $0))
check_busybox
cmd=(
	docker run
	--rm
	--name ${job_id}
	--hostname $host.compass-ci.net
	--cpus $nr_cpu
	-m $memory
	--tmpfs /tmp:rw,exec,nosuid,nodev
	-e CCI_SRC=/c/compass-ci
	-v ${load_path}/lkp:/lkp
	-v ${load_path}/opt:/opt
	-v ${DIR}/bin:/root/sbin:ro
	-v $CCI_SRC:/c/compass-ci:ro
	-v /srv/git:/srv/git:ro
	-v /srv/result:/srv/result:ro
	-v /etc/localtime:/etc/localtime:ro
	-v ${busybox_path}:/usr/local/bin/busybox
	--log-driver json-file
	--log-opt max-size=10m
	--oom-score-adj="-1000"
	${docker_image}
	/root/sbin/entrypoint.sh
)

"${cmd[@]}" 2>&1 | tee -a "$log_dir"
