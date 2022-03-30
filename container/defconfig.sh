#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $LKP_SRC/lib/yaml.sh

load_cci_defaults()
{
	shopt -s nullglob

        yaml_file=(
                /etc/compass-ci/defaults/*.yaml
                /etc/compass-ci/service/*.yaml
                /etc/compass-ci/accounts/*.yaml
                "$HOME"/.config/compass-ci/defaults/*.yaml
        )
	for i in "${yaml_file[@]}"
	do
		create_yaml_variables "$i"
	done
}

load_service_authentication()
{
	shopt -s nullglob
	file_name='/etc/compass-ci/passwd.yaml'
	[ -f $file_name ] || return
	create_yaml_variables $file_name
}

load_pack_vars()
{
	shopt -s nullglob
	file_name="$HOME/.config/compass-ci/pack.yaml"
	[ -f $file_name ] || return
	create_yaml_variables $file_name
}

load_service_config()
{
        shopt -s nullglob
        file_name="/etc/compass-ci/setup.yaml"
        [ -f $file_name ] || return
        create_yaml_variables $file_name
}

docker_rm()
{
	container=$1
	[ -n "$(docker ps -aqf name="^${container}$")" ] || return 0
	docker stop $container
	docker rm -f $container
}

check_auth_es_ready()
{
	local port=$1
	load_service_authentication
	local i
	for i in {1..30}
	do

		curl -s localhost:$port -u $ES_USER:$ES_PASSWORD> /dev/null && return
		sleep 2
	done
}

check_service_ready()
{
	local port=$1
	local i
	for i in {1..30}
	do
		curl -s localhost:$port > /dev/null && return
		sleep 2
	done
}

push_image()
{
	[ "$suite" == "self-test" ] && return

        local local_docker_hub="$DOCKER_REGISTRY_HOST:$DOCKER_REGISTRY_PORT"
        local src_tag=$1
        local dst_tag="$local_docker_hub/$src_tag"

        docker tag "$src_tag" "$dst_tag"
        docker push "$dst_tag"
}

docker_skip_rebuild()
{
	tag=$1
	[ "$skip_build_image" != "true" ] && return
	docker image inspect $tag > /dev/null 2>&1
	[ "$?" == "0" ] && exit 1
}
