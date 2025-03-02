#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

[ "$LKP_SRC" ] || LKP_SRC=/c/lkp-tests

. $LKP_SRC/lib/yaml.sh

: ${job_id:=$$}
: ${docker_image:="centos:7"}
: ${hostname:="dc-8g-1"}
: ${host_dir:="${HOME}/.cache/compass-ci/provider/hosts/$hostname"}
: ${log_file:="${HOME}/.cache/compass-ci/provider/logs/$hostname"}

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

if command -v kubectl >/dev/null; then
	squid_host=$(kubectl get svc -n ems1 | grep "^squid-${HOSTNAME} "| awk '{print $3}')
fi

DIR=$(dirname $(realpath $0))
check_busybox
check_docker_sock
check_package_optimization_strategy

# Determine container runtime (podman or docker)
container_runtime=$(command -v podman || command -v docker)
if [[ -z "$container_runtime" ]]; then
	echo "Error: Neither podman nor docker is installed." >&2
	exit 1
fi

# Base command
cmd=(
	"$container_runtime" run
	--rm
	--name "$hostname"
	--hostname "$host.compass-ci.net"
	-m "$memory"
	--tmpfs /tmp:rw,exec,nosuid,nodev
	--net=host
	-e SQUID_HOST="$squid_host"
	-e CCI_SRC=/c/compass-ci
	-e CCACHE_UMASK=002
	-e CCACHE_DIR="$CCACHE_DIR"
	-e CCACHE_COMPILERCHECK=content
	-e CCACHE_ENABLE="$ccache_enable"
	-v "${host_dir}/lkp:/lkp"
	-v "${DIR}/bin/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro"
	-v "$CCI_SRC:/c/compass-ci:ro"
	-v "/srv/git:/srv/git:ro"
	-v "$host_dir/result_root:$result_root"
	-v "${busybox_path}:/usr/local/bin/busybox"
	--log-driver json-file
	--log-opt max-size=10m
	--oom-score-adj="-1000"
)

# Add --cpus if nr_cpu is provided
if [[ -n "$nr_cpu" ]]; then
	cmd+=(--cpus "$nr_cpu")
fi

# Add --privileged if running as root
if [[ $(id -u) -eq 0 ]]; then
	cmd+=(--privileged)
	cmd+=(-v /sys/kernel/debug:/sys/kernel/debug:ro)
fi

# Add Docker-specific options if runtime is docker
if [[ "$container_runtime" == *"docker"* ]]; then
	cmd+=(
	-v /var/run/docker.sock:/var/run/docker.sock
	-v /usr/bin/docker:/usr/bin/docker:ro
)
else
	cmd+=(
	--replace
)
fi

# Add volumes_from if provided
if [[ -n "$volumes_from" ]]; then
	cmd+=(--volumes-from "$volumes_from")
fi

# package cache
[ -n "$ENABLE_PACKAGE_CACHE" ] &&
case "$os" in
	debian|ubuntu)
		mkdir -p $CACHE_DIR/$osv/archives
		mkdir -p $CACHE_DIR/$osv/lists
		cmd+=(-v "$CACHE_DIR/$osv/archives:/var/cache/apt/archives")
		cmd+=(-v "$CACHE_DIR/$osv/lists:/var/lib/apt/lists")
		;;
	openeuler|centos|rhel|fedora)
		mkdir -p $CACHE_DIR/$osv
		cmd+=(-v "$CACHE_DIR/$osv:/var/cache/dnf")
		;;
esac

record_startup_log() {
    # Capture the current timestamp in the desired format
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')

    # Write the startup log to the log file
    echo "${start_time} starting CONTAINER"
    echo "job_id ${job_id}"
    echo "result_root ${result_root}"
    echo
}

record_end_log() {
    # Calculate the current time and duration in minutes
    local current_time=$(date +%s)
    local duration=$(( (current_time - startup_time) / 60 ))
    local duration_rounded=$(echo "scale=2; $duration" | bc)

    # Append the duration to the log file
    echo -e "\nTotal CONTAINER duration: ${duration_rounded} minutes"
}

JOB_DONE_FIFO_PATH=/tmp/job_completion_fifo
echo "boot: $job_id" >> $JOB_DONE_FIFO_PATH
startup_time=$(date +%s)
record_startup_log >> "$log_file"

# Execute the command
echo "less $log_file"
"${cmd[@]}" "$docker_image" /usr/local/bin/entrypoint.sh 2>&1 |
	awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; fflush(); }' | tee -a "$log_file"

record_end_log >> "$log_file"
echo "done: $job_id" >> $JOB_DONE_FIFO_PATH
