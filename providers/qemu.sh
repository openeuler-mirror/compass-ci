#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# - hostname

. $LKP_SRC/lib/yaml.sh
. $CCI_SRC/container/defconfig.sh
. $CCI_SRC/lib/log.sh
. $LKP_SRC/lib/upload.sh

load_cci_defaults

: ${hostname:="vm-1p8g-1"}
: ${log_file:=/srv/provider/logs/$hostname}

main()
{
	WORKSPACE=${WORKSPACE:-$(pwd)}

	log_info "start vm: $hostname" | tee -a $log_file
	log_info "chdir to workspace: $WORKSPACE" | tee -a $log_file

	cd $WORKSPACE

	# unicast prefix: x2, x6, xA, xE
	export mac=$(echo $hostname | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/0a-\1-\2-\3-\4-\5/')
	echo hostname: $hostname
	echo mac: $mac
	echo $mac > mac
	echo "arp -n | grep ${mac//-/:}" > ip.sh
	chmod +x ip.sh

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

	[ -n "$id" ] && upload_files -t $(cat job_id) $log_file

	# Allow fluentd sufficient time to read the contents of the log file
	sleep 5
}

main
