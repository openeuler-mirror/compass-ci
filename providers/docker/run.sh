#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

[ "$LKP_SRC" ] || LKP_SRC=/c/lkp-tests

. $LKP_SRC/lib/yaml.sh

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
create_yaml_variables "$LKP_SRC/hosts/${host}"

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

check_docker_sock()
{
	if [ "$need_docker_sock" == "y" ]; then
		mount_docker_sock="-v /var/run/docker.sock:/var/run/docker.sock:ro"
	fi
}

check_package_optimization_strategy()
{	
	if [ ! -n "${memory_minimum}" ];then
		memory_minimum="8"
	fi
	memory="${memory_minimum}g"
	[ -z "$ccache_enable" ] && return 0
	[ -z "$cpu_minimum" ] || nr_cpu=$cpu_minimum

	if [ "$ccache_enable" = "True" ]; then
		ccache_name=$(docker ps | grep k8s_ccache_ccache|grep -v pause|awk '{print $NF}')
		[ $ccache_name ] || ccache_name=ccache
		volumes_from="--volumes-from $ccache_name"
		CCACHE_DIR=/etc/.ccache
	fi
}

squid_host=$(kubectl get svc -n ems1 | grep "^squid-${HOSTNAME} "| awk '{print $3}')

DIR=$(dirname $(realpath $0))
check_busybox
check_docker_sock
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
	-e SQUID_HOST=$squid_host
	-e CCI_SRC=/c/compass-ci
	-e CCACHE_UMASK=002
	-e CCACHE_DIR=$CCACHE_DIR
	-e CCACHE_COMPILERCHECK=content
	-e CCACHE_ENABLE=$ccache_enable
	-v /sys/kernel/debug:/sys/kernel/debug:ro
	$mount_docker_sock
	-v /usr/bin/docker:/usr/bin/docker:ro
	-v ${load_path}/lkp:/lkp
	-v ${load_path}/opt:/opt
	-v ${DIR}/bin:/root/sbin:ro
	-v $CCI_SRC:/c/compass-ci:ro
	-v /srv/git:/srv/git:ro
	-v /srv/result:/srv/result:ro
	-v ${busybox_path}:/usr/local/bin/busybox
	$volumes_from
	--log-driver json-file
	--log-opt max-size=10m
	--oom-score-adj="-1000"
	${docker_image}
	/root/sbin/entrypoint.sh
)

echo "less $log_dir"
"${cmd[@]}" 2>&1 | awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; fflush(); }' | tee -a "$log_dir"
