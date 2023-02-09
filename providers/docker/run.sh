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

check_package_optimization_strategy()
{
	[ -z "$bin_shareable" ] && return 0
	[ -z "$ccache_enable" ] && return 0
	[ -z "$cpu_minimum" ] || nr_cpu=$cpu_minimum

	[ "$memory_minimun" = "auto" ] || memory=$memory_minimun

	if [ "$bin_shareable" = "True" ] || [ "$ccache_enable" = "True" ]; then
		volumes_from="--volumes-from ccache"
		CCACHE_DIR=/etc/.ccache
	fi
}

DIR=$(dirname $(realpath $0))
check_busybox
check_package_optimization_strategy
cmd=(
	docker run
	--rm
	--name ${job_id}
	--hostname $host.compass-ci.net
	# --cpus $nr_cpu
	-m $memory
	--tmpfs /tmp:rw,exec,nosuid,nodev
	--privileged
	--net=host
	-e CCI_SRC=/c/compass-ci
	-e CCACHE_UMASK=002
	-e CCACHE_DIR=$CCACHE_DIR
	-e CCACHE_COMPILERCHECK=content
	-e CCACHE_ENABLE=$ccache_enable
	-v ${load_path}/lkp:/lkp
	-v ${load_path}/opt:/opt
	-v ${DIR}/bin:/root/sbin:ro
	-v $CCI_SRC:/c/compass-ci:ro
	-v /srv/git:/srv/git:ro
	-v /srv/result:/srv/result:ro
	# --volumes-from yum-cache
	-v ${busybox_path}:/usr/local/bin/busybox
	$volumes_from
	--log-driver json-file
	--log-opt max-size=10m
	--oom-score-adj="-1000"
	${docker_image}
	/root/sbin/entrypoint.sh
)

"${cmd[@]}" 2>&1 | awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; fflush(); }' | tee -a "$log_dir"
