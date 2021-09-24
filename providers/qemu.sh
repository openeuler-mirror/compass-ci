#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - hostname

. $LKP_SRC/lib/yaml.sh
. $CCI_SRC/container/defconfig.sh
. $CCI_SRC/lib/log.sh
. $LKP_SRC/lib/upload.sh

load_cci_defaults

: ${hostname:="vm-1p1g-1"}
: ${queues:="vm-1p1g.$(arch)"}
: ${log_file:=/srv/cci/serial/logs/$hostname}

set_host_info()
{
	# use "," replace " "
	local api_queues=$(echo $queues | sed -r 's/ +/,/g')
	curl -X PUT "http://${SCHED_HOST:-172.17.0.1}:${SCHED_PORT:-3000}/set_host_mac?hostname=${hostname}&mac=${mac}"
	curl -X PUT "http://${SCHED_HOST:-172.17.0.1}:${SCHED_PORT:-3000}/set_host2queues?host=${hostname}&queues=${api_queues}"
}

del_host_info()
{
	curl -X PUT "http://${SCHED_HOST:-172.17.0.1}:${SCHED_PORT:-3000}/del_host_mac?mac=${mac}" > /dev/null 2>&1
	curl -X PUT "http://${SCHED_HOST:-172.17.0.1}:${SCHED_PORT:-3000}/del_host2queues?host=${hostname}" > /dev/null 2>&1
}

release_mem()
{
	[ -n "$index" ] && command -v ruby && ruby -r "${CCI_SRC}/providers/lib/common.rb" -e "release_mem '$hostname'"
}

post_work()
{
	del_host_info
	release_mem
	lockfile-remove --lock-name $lockfile
}

get_lock()
{
	[[ $(($retry_time % $retry_remain_times)) -eq 0 ]] && {
		log_info "uuid: $UUID" | tee -a $log_file
		log_info "try to get lock: $lockfile" | tee -a $log_file
		log_info "already retry times: $retry_time" | tee -a $log_file
	}

	lockfile-create -q --lock-name -p --retry 0 $lockfile || return 1
	log_info "vm got lock successed: $lockfile, uuid: $UUID" | tee -a $log_file
}

main()
{
	WORKSPACE=${WORKSPACE:-$(pwd)}

	log_info "start vm: $hostname" | tee -a $log_file
	log_info "chdir to workspace: $WORKSPACE" | tee -a $log_file

	cd $WORKSPACE

	# why lock this?
	# because one mac match one vm, and only one vm with unique mac can running/requesting at any time.

	lockfile="${hostname}.lock"

	local retry_remain_times=600
	local retry_time=0
	while ! get_lock; do
		sleep 1
		retry_time=$(($retry_time + 1))
	done

	# unicast prefix: x2, x6, xA, xE
	export mac=$(echo $hostname | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/0a-\1-\2-\3-\4-\5/')
	echo hostname: $hostname
	echo mac: $mac
	echo $mac > mac
	echo "arp -n | grep ${mac//-/:}" > ip.sh
	chmod +x ip.sh

	set_host_info
	trap post_work EXIT

	(
		if [[ $hostname =~ ^(.*)-[0-9]+$ ]]; then
			tbox_group=${BASH_REMATCH[1]}
		else
			tbox_group=$hostname
		fi

		host=${tbox_group%.*}

		# cleanup definitions from HW testbox
		# to avoid mixing up with definitions from the below VM testbox
		unset nr_hdd_partitions
		unset nr_ssd_partitions
		unset hdd_partitions
		unset ssd_partitions
		unset rootfs_partition
		unset rootfs_disk
		create_yaml_variables "$LKP_SRC/hosts/${host}"

		source "$CCI_SRC/providers/$provider/${template}.sh"
	)

	log_info "pwd: $(pwd), hostname: $hostname, mac: $mac" | tee -a $log_file
	log_info "vm finish run, release lock: $lockfile, uuid: $UUID" | tee -a $log_file

	[ -n "$id" ] && upload_files -t $(cat job_id) $log_file

	# Allow fluentd sufficient time to read the contents of the log file
	sleep 5
}

main
