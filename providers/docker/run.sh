#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $LKP_SRC/lib/yaml.sh

: ${job_id:=$$}
: ${docker_image:="centos:7"}
: ${load_path:="${HOME}/jobs"}
: ${hostname:="dc-1g-1"}
: ${log_dir:="/srv/cci/serial/logs/$hostname"}

if [[ $hostname =~ ^(.*)-[0-9]+$ ]]; then
	tbox_group=${BASH_REMATCH[1]}
else
	tbox_group=$hostname
fi
host=${tbox_group%.*}

create_yaml_variables "$LKP_SRC/hosts/${host}"

DIR=$(dirname $(realpath $0))
busybox_path=$(command -v busybox)
cmd=(
	docker run
	--rm
	--name ${job_id}
	--hostname $host.compass-ci.net
	-m $memory
	--tmpfs /tmp:rw,exec,nosuid,nodev
	-e CCI_SRC=/c/compass-ci
	-v ${load_path}/lkp:/lkp
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
