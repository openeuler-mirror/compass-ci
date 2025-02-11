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

load_cci_secrets()
{
	shopt -s nullglob

	secrets_file=/etc/compass-ci/info-file
	secret_keys=($(echo $*))

	for secret_key in ${secret_keys[@]}
	do
		eval $(awk '{if ($2 == "'$secret_key'") print $2"="$3}' $secrets_file)
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

check_es_ready()
{
	load_service_authentication
	load_cci_defaults
	for i in {1..30}
	do

		status_code=$(curl -sSIL -u "${ES_SUPER_USER}:${ES_SUPER_PASSWORD}" -w "%{http_code}\n" -o /dev/null -XGET "http://${ES_HOST}:${ES_PORT}")
		[ "${status_code}" -eq 200 ] && return 0
		sleep 2
	done

	return 1
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

download_repo()
{
	local repo="$1"
	local git_branch="$2"
	load_service_authentication

	[ -d "./$repo" ] && rm -rf ./"$repo"
	[ "$git_branch" ] || git_branch=$(awk '/^git_branch:\s/ {print $2; exit}' /etc/compass-ci/defaults/*.yaml)
	umask 022 && git clone -b "$git_branch" https://${GITEE_ID}:${GITEE_PASSWORD}@gitee.com/openeuler-customization/"$repo"
}

push_image_remote()
{
	load_cci_defaults
	load_service_authentication

	[ "$DOCKER_REGISTRY_HOST" = "registry.kubeoperator.io" ] && [ "$DOCKER_PUSH_REGISTRY_PORT" = "8083" ] && {
        	local remote_docker_hub="$DOCKER_REGISTRY_HOST:$DOCKER_PUSH_REGISTRY_PORT"
        	local src_tag=$1
        	local dst_tag="$remote_docker_hub/$src_tag"
		docker login "$remote_docker_hub" -u $DOCKER_REGISTRY_USER -p $DOCKER_REGISTRY_PASSWORD
		
        	docker tag "$src_tag" "$dst_tag"
        	docker push "$dst_tag"
        	rm -f /root/.docker/config.json
	}
}

start_pod()
{
	[ ! -d "k8s/" ] && return
	[ "$(ls -A k8s)" = "" ] && return

	load_service_config
	load_cci_defaults
	if [ "$DOCKER_REGISTRY_HOST" = "registry.kubeoperator.io" ] && [ "$DOCKER_PUSH_REGISTRY_PORT" = "8083" ]; then
		kubectl delete -f k8s/ -n $NAMESPACE >/dev/null 2>&1
		kubectl create -f k8s/ -n $NAMESPACE
		exit 1
	fi
}

start_etcd_pod()
{
        [ ! -d "k8s/" ] && return
        [ "$(ls -A k8s)" = "" ] && return
        echo "start etcd pod"

        load_cci_defaults
        if [ "$DOCKER_REGISTRY_HOST" = "registry.kubeoperator.io" ] && [ "$DOCKER_PUSH_REGISTRY_PORT" = "8083" ]; then
                kubectl delete -f k8s/ -n ems1 >/dev/null 2>&1
                kubectl create -f k8s/ -n ems1
        fi

        sleep 60
        load_service_authentication

        etcd_container_id=$(docker ps|grep k8s_etcd_etcd-0 | awk '{print $1}')
        docker exec -d ${etcd_container_id} sh -c "etcdctl user add ${ETCD_USER}:${ETCD_PASSWORD};etcdctl auth enable"
        exit 1
}

config_yaml()
{
        file="/etc/compass-ci/remote-hosts"
	[ -f $file ] || return
        names=($(cat $file | awk '{print $1}' | grep -v "^#"))
        for name in ${names[@]}
        do
                sed \
                    -e "s#SQUID_NAME#squid-${name}#g" \
                    -e "s#NODE_NAME#${name}#g" \
                    squid.yaml > k8s/squid-${name}.yaml
        done
}

# 获取系统内存信息并计算可用内存
get_available_memory() {
  # 从 /proc/meminfo 提取 MemTotal (单位 kB)
  local memtotal_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')

  # 转换为 GB (1 GB = 1024*1024 kB)
  local memtotal_gb=$(echo "scale=6; $memtotal_kb / 1048576" | bc -l)

  # 计算中间值: sqrt(memtotal_gb) * 1024 (保留小数)
  local intermediate=$(echo "scale=6; sqrt($memtotal_gb) * 1024" | bc -l)

  # 三值排序取中位数 (使用数值排序支持浮点)
  local sorted_values=($(printf "%s\n" 1024 30720 "$intermediate" | sort -g))

  # 取中间值并截断小数部分
  echo "${sorted_values[1]}" | awk '{print int($1)}'
}
