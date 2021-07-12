#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - hostname

. $LKP_SRC/lib/yaml.sh
. $CCI_SRC/container/defconfig.sh
. $CCI_SRC/lib/log.sh

load_cci_defaults

: ${hostname:="vm-1p1g-1"}
: ${queues:="vm-1p1g.$(arch)"}

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

get_lock()
{
	lockfile-create -p --retry 0 $lockfile > /dev/null 2>&1 || return 1
	log_info "vm got lock successed: $lockfile"
}

main()
{
	# why lock this?
	# because one mac match one vm, and only one vm with unique mac can running/requesting at any time.

	local lockfile="${hostname}/lockfile"
	mkdir -p $hostname

	while ! get_lock; do
		sleep 1
	done

	# unicast prefix: x2, x6, xA, xE
	export mac=$(echo $hostname | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/0a-\1-\2-\3-\4-\5/')
	echo hostname: $hostname
	echo mac: $mac
	echo $mac > mac
	echo "arp -n | grep ${mac//-/:}" > ip.sh
	chmod +x ip.sh

	set_host_info
	trap del_host_info EXIT

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

	log_info "vm finish run, release lock: $lockfile"
	lockfile-remove $lockfile
}

main
