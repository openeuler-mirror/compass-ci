#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $LKP_SRC/lib/yaml.sh

: ${docker_image:="centos:7"}
: ${load_path:="${HOME}/jobs"}
: ${hostname:="dc-1g-1"}

if [[ $hostname =~ ^(.*)-[0-9]+$ ]]; then
	tbox_group=${BASH_REMATCH[1]}
else
	tbox_group=$hostname
fi
host=${tbox_group%%--*}

create_yaml_variables "$LKP_SRC/hosts/${host}"

DIR=$(dirname $(realpath $0))
cmd=(
	docker run
	--rm
	-m $memory
	--mount type=tmpfs,destination=/tmp
	-e CCI_SRC=/c/commpass-ci
	-v ${load_path}/lkp:/lkp
	-v ${DIR}/bin:/root/bin:ro
	-v $CCI_SRC:/c/commpass-ci
	-v /srv/git:/srv/git:ro
	--oom-score-adj="-1000"
	${docker_image}
	/root/bin/entrypoint.sh
)

"${cmd[@]}"
