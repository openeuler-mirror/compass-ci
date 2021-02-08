#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $LKP_SRC/lib/yaml.sh

load_cci_defaults()
{
	shopt -s nullglob

        yaml_file=(
                /etc/compass-ci/defaults/*.yaml
                /etc/compass-ci/accounts/*.yaml
                "$HOME"/.config/compass-ci/defaults/*.yaml
        )
	for i in "${yaml_file[@]}"
	do
		create_yaml_variables "$i"
	done
}

docker_rm()
{
	container=$1
	[ -n "$(docker ps -aqf name="^${container}$")" ] || return 0
	docker stop $container
	docker rm -f $container
}

set_es_indices()
{
	find $CCI_SRC/sbin/ -name "es-*-mapping.sh" -exec sh {} \;
}

push_image()
{
        local local_docker_hub="$DOCKER_REGISTRY_HOST:$DOCKER_REGISTRY_PORT"
        local src_tag=$1
        local dst_tag="$local_docker_hub/$src_tag"

        docker tag "$src_tag" "$dst_tag"
        docker push "$dst_tag"
}

docker_skip_rebuild()
{
	tag=$1
	[ "$action" != "run-only" ] && return
	docker image inspect $tag > /dev/null 2>&1
	[ "$?" == "0" ] && exit 1
}
