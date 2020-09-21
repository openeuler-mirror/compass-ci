#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

. $LKP_SRC/lib/yaml.sh

load_cci_defaults()
{
	shopt -s nullglob

	for i in /etc/compass-ci/defaults/*.yaml $HOME/.config/compass-ci/defaults/*.yaml
	do
		create_yaml_variables "$i"
	done
}

docker_rm()
{
	container=$1
	[ -n "$(docker ps -aqf name="^${container}$")" ] && docker rm -f $container
}
